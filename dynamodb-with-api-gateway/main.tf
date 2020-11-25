# Create dynamo db table
resource "aws_dynamodb_table" "example" {
  name         = "example"
  hash_key     = "id"
  range_key    = "range"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "range"
    type = "S"
  }
}

# The policy document to access the role
data "aws_iam_policy_document" "dynamodb_table_policy_example" {
  depends_on = [aws_dynamodb_table.example]
  statement {
    sid = "dynamodbtablepolicy"

    actions = [
      "dynamodb:Query"
    ]

    resources = [
      aws_dynamodb_table.example.arn,
    ]
  }
}

# The IAM Role for the execution
resource "aws_iam_role" "api_gateway_dynamodb_example" {
  name               = "api_gateway_dynamodb_example"
  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": "iamroletrustpolicy"
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy" "example_policy" {
  name = "example_policy"
  role = aws_iam_role.api_gateway_dynamodb_example.id
  policy = data.aws_iam_policy_document.dynamodb_table_policy_example.json
}

# API Gateway for dynamodb
resource "aws_api_gateway_rest_api" "exampleApi" {
  name        = "exampleApi"
  description = "Example API"
}

# Create a resource
resource "aws_api_gateway_resource" "resource-example" {
  rest_api_id = aws_api_gateway_rest_api.exampleApi.id
  parent_id   = aws_api_gateway_rest_api.exampleApi.root_resource_id
  path_part   = "{val}"
}

# Create a Method
resource "aws_api_gateway_method" "get-example-method" {
  rest_api_id   = aws_api_gateway_rest_api.exampleApi.id
  resource_id   = aws_api_gateway_resource.resource-example.id
  http_method   = "GET"
  authorization = "NONE"
}

# Create an integration with the dynamo db
resource "aws_api_gateway_integration" "get-example-integration" {
  rest_api_id             = aws_api_gateway_rest_api.exampleApi.id
  resource_id             = aws_api_gateway_resource.resource-example.id
  http_method             = aws_api_gateway_method.get-example-method.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:dynamodb:action/Query"
  credentials             = aws_iam_role.api_gateway_dynamodb_example.arn
  request_templates = {
    "application/json" = <<EOF
      {
        "TableName": "${aws_dynamodb_table.example.name}",
        "KeyConditionExpression": "id = :val",
        "ExpressionAttributeValues": {
          ":val": {
              "S": "$input.params('val')"
          }
        }
      }
    EOF
  }
}

#Add a response code with the method
resource "aws_api_gateway_method_response" "get-example-response-200" {
  rest_api_id = aws_api_gateway_rest_api.exampleApi.id
  resource_id = aws_api_gateway_resource.resource-example.id
  http_method = aws_api_gateway_method.get-example-method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Create a response template for dynamo db structure
resource "aws_api_gateway_integration_response" "get-example-response" {
  depends_on  = [aws_api_gateway_integration.get-example-integration]
  rest_api_id = aws_api_gateway_rest_api.exampleApi.id
  resource_id = aws_api_gateway_resource.resource-example.id
  http_method = aws_api_gateway_method.get-example-method.http_method
  status_code = aws_api_gateway_method_response.get-example-response-200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  response_templates = {
    "application/json" = <<EOF
      #set($inputRoot = $input.path('$'))
      {
        #foreach($elem in $inputRoot.Items)
        "id": "$elem.id.S",
        #if($foreach.hasNext),#end
        #end
      }
    EOF
  }
}

# Deploying API Gateway
resource "aws_api_gateway_deployment" "exampleApiDeployment" {
  depends_on = [aws_api_gateway_integration.get-example-integration]

  rest_api_id = aws_api_gateway_rest_api.exampleApi.id
  stage_name  = var.stage_name

  variables = {
    "deployedAt" = timestamp()
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Custom domain for the API Gateway
resource "aws_api_gateway_domain_name" "exampleCustomDomain" {
  certificate_arn = var.certificate_arn
  domain_name     = var.domain_name
  security_policy = "TLS_1_2"
}

# Route53 Record binding
resource "aws_route53_record" "exampleCustomDomainRecord" {
  name    = aws_api_gateway_domain_name.exampleCustomDomain.domain_name
  type    = "A"
  zone_id = var.route53_zone

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.exampleCustomDomain.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.exampleCustomDomain.cloudfront_zone_id
  }
}

# Base path mapping
resource "aws_api_gateway_base_path_mapping" "exampleMapping" {
  api_id      = aws_api_gateway_rest_api.exampleApi.id
  stage_name  = aws_api_gateway_deployment.exampleApiDeployment.stage_name
  domain_name = aws_api_gateway_domain_name.exampleCustomDomain.domain_name
}
