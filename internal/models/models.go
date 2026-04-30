package models

import (
	"time"

	"github.com/aws/aws-lambda-go/events"
)

// User representa la entidad principal en DynamoDB y MongoDB
type User struct {
	UserId string `json:"userId" dynamodbav:"userId" bson:"userId"`
	Name   string `json:"name" dynamodbav:"name" bson:"name"`
	Email  string `json:"email" dynamodbav:"email" bson:"email"`
}

// TraceLog representa el log de auditoría para MongoDB
type TraceLog struct {
	Action    string    `bson:"action"`
	UserId    string    `bson:"userId"`
	Timestamp time.Time `bson:"timestamp"`
}

// Helper para respuestas estandarizadas de API Gateway
func APIResponse(status int, body string) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Body:       body,
		Headers: map[string]string{
			"Content-Type":                 "application/json",
			"Access-Control-Allow-Origin":  "https://haroldsoftware.com",
			"Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
		},
	}, nil
}