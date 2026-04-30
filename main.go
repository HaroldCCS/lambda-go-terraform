package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// Definimos la estructura del Usuario
type User struct {
	UserId string `json:"userId" dynamodbav:"userId"`
	Name   string `json:"name" dynamodbav:"name"`
	Email  string `json:"email" dynamodbav:"email"`
}

var dynamoClient *dynamodb.Client
var tableName string

func init() {
	tableName = os.Getenv("TABLE_NAME")
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		log.Fatalf("Error cargando config de AWS: %v", err)
	}
	dynamoClient = dynamodb.NewFromConfig(cfg)
}

func HandleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	log.Printf("Procesando petición: %s %s", request.HTTPMethod, request.Path)

	switch request.HTTPMethod {
	case "POST": // CREATE
		var user User
		json.Unmarshal([]byte(request.Body), &user)
		
		item, _ := attributevalue.MarshalMap(user)
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: aws.String(tableName),
			Item:      item,
		})
		if err != nil {
			return response(500, "Error guardando usuario"), nil
		}
		return response(201, "Usuario creado"), nil

	case "GET": // READ
		userId := request.QueryStringParameters["userId"]
		if userId == "" {
			return response(400, "userId es requerido"), nil
		}

		result, err := dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
			TableName: aws.String(tableName),
			Key: map[string]types.AttributeValue{
				"userId": &types.AttributeValueMemberS{Value: userId},
			},
		})
		if err != nil || result.Item == nil {
			return response(404, "Usuario no encontrado"), nil
		}

		var user User
		attributevalue.UnmarshalMap(result.Item, &user)
		body, _ := json.Marshal(user)
		return response(200, string(body)), nil

	case "PUT": // UPDATE
		var user User
		json.Unmarshal([]byte(request.Body), &user)
		
		item, _ := attributevalue.MarshalMap(user)
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: aws.String(tableName),
			Item:      item,
		})
		if err != nil {
			return response(500, "Error actualizando usuario"), nil
		}
		return response(200, "Usuario actualizado"), nil

	case "DELETE": // DELETE
		userId := request.QueryStringParameters["userId"]
		_, err := dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: aws.String(tableName),
			Key: map[string]types.AttributeValue{
				"userId": &types.AttributeValueMemberS{Value: userId},
			},
		})
		if err != nil {
			return response(500, "Error eliminando usuario"), nil
		}
		return response(200, "Usuario eliminado"), nil

	default:
		return response(405, "Método no soportado"), nil
	}
}

// Función auxiliar para responder de forma limpia
func response(status int, body string) events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Body:       body,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}
}

func main() {
	lambda.Start(HandleRequest)
}