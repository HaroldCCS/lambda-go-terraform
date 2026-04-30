package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"time"

	"lambda-go-project/internal/models"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	dynamoClient *dynamodb.Client
	mongoColl    *mongo.Collection
	tableName    string
)

func init() {
	ctx := context.TODO()
	tableName = os.Getenv("TABLE_NAME")
	
	// 1. Cargar configuración base de AWS
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Error cargando config de AWS: %v", err)
	}
	dynamoClient = dynamodb.NewFromConfig(cfg)

	// 2. Obtener URI de MongoDB desde SSM Parameter Store
	mURI := getMongoURIFromSSM(ctx, cfg)

	// 3. Conectar a MongoDB
	mOpts := options.Client().ApplyURI(mURI).SetMaxPoolSize(1)
	client, err := mongo.Connect(ctx, mOpts)
	if err != nil {
		log.Fatalf("Error conectando a Mongo: %v", err)
	}
	mongoColl = client.Database("logs_db").Collection("traces")
}

// Función auxiliar para recuperar el parámetro seguro
func getMongoURIFromSSM(ctx context.Context, cfg aws.Config) string {
	paramName := os.Getenv("MONGO_URI") // Ahora usamos el nombre del parámetro
	ssmClient := ssm.NewFromConfig(cfg)

	out, err := ssmClient.GetParameter(ctx, &ssm.GetParameterInput{
		Name:           aws.String(paramName),
		WithDecryption: aws.Bool(true), // Importante para SecureString
	})
	if err != nil {
		log.Fatalf("Error obteniendo MONGO_URI desde SSM: %v", err)
	}

	return *out.Parameter.Value
}

func HandleSQS(ctx context.Context, event events.SQSEvent) error {
	for _, record := range event.Records {
		var u models.User
		if err := json.Unmarshal([]byte(record.Body), &u); err != nil {
			log.Printf("Error unmarshaling record: %v", err)
			return err
		}

		// 1. Guardar en DynamoDB
		if err := saveToDynamo(ctx, u); err != nil {
			log.Printf("Error guardando en Dynamo: %v", err)
			return err
		}

		// 2. Trazabilidad en MongoDB
		saveTrace(ctx, u.UserId)
	}
	return nil
}

func saveToDynamo(ctx context.Context, u models.User) error {
	item, err := attributevalue.MarshalMap(u)
	if err != nil {
		return err
	}
	_, err = dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})
	return err
}

func saveTrace(ctx context.Context, userId string) {
	trace := models.TraceLog{
		Action:    "ASYNC_CREATE",
		UserId:    userId,
		Timestamp: time.Now(),
	}
	_, err := mongoColl.InsertOne(ctx, trace)
	if err != nil {
		log.Printf("Error insertando traza en Mongo: %v", err)
	}
}

func main() {
	lambda.Start(HandleSQS)
}