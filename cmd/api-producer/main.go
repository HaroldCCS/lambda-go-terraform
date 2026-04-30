package main

import (
	"context"
	"encoding/json"
	"os"

	"lambda-go-project/internal/models" 
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

var (
	dynamoClient *dynamodb.Client
	sqsClient    *sqs.Client
	tableName    string
	sqsURL       string
)

func init() {
	tableName = os.Getenv("TABLE_NAME")
	sqsURL = os.Getenv("SQS_URL")
	cfg, _ := config.LoadDefaultConfig(context.TODO())
	dynamoClient = dynamodb.NewFromConfig(cfg)
	sqsClient = sqs.NewFromConfig(cfg)
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	switch req.HTTPMethod {
	case "POST":
		return handleCreate(ctx, req)
	case "GET":
		return handleGet(ctx, req)
	case "PUT":
		return handleUpdate(ctx, req)
	case "DELETE":
		return handleDelete(ctx, req)
	default:
		return models.APIResponse(405, `{"error": "Method not allowed"}`)
	}
}

func handleCreate(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	_, err := sqsClient.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    aws.String(sqsURL),
		MessageBody: aws.String(req.Body),
	})
	if err != nil {
		return models.APIResponse(500, `{"error": "Failed to enqueue request"}`)
	}
	return models.APIResponse(202, `{"message": "User creation in progress"}`)
}

func handleGet(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	id := req.QueryStringParameters["userId"]
	res, err := dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(tableName),
		Key:       map[string]types.AttributeValue{"userId": &types.AttributeValueMemberS{Value: id}},
	})
	if err != nil || res.Item == nil {
		return models.APIResponse(404, `{"error": "Not found"}`)
	}
	var u models.User
	attributevalue.UnmarshalMap(res.Item, &u)
	body, _ := json.Marshal(u)
	return models.APIResponse(200, string(body))
}

func handleUpdate(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var u models.User
	json.Unmarshal([]byte(req.Body), &u)
	item, _ := attributevalue.MarshalMap(u)
	_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(tableName), Item: item})
	if err != nil {
		return models.APIResponse(500, `{"error": "Update failed"}`)
	}
	return models.APIResponse(200, `{"message": "Updated"}`)
}

func handleDelete(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	id := req.QueryStringParameters["userId"]
	_, err := dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(tableName),
		Key:       map[string]types.AttributeValue{"userId": &types.AttributeValueMemberS{Value: id}},
	})
	if err != nil {
		return models.APIResponse(500, `{"error": "Delete failed"}`)
	}
	return models.APIResponse(200, `{"message": "Deleted"}`)
}

func main() { lambda.Start(HandleRequest) }