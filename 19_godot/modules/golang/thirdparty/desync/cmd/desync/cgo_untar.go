package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
	"go.opentelemetry.io/otel/trace"
)

//export DesyncUntar
func DesyncUntar(storeUrl *C.char, indexUrl *C.char, outputDir *C.char, cacheDir *C.char) C.int {
	store := C.GoString(storeUrl)
	index := C.GoString(indexUrl)
	output := C.GoString(outputDir)
	cache := C.GoString(cacheDir)

	if store == "" || index == "" || output == "" {
		fmt.Println("Error: storeUrl, indexUrl, and outputDir are required")
		return 1
	}

	args := []string{"--no-same-owner", "--store", store, "--index", index, output}
	if cache != "" {
		args = append(args, "--cache", cache)
	}

	cmd := newUntarCommand(context.Background())
	cmd.SetArgs(args)
	_, err := cmd.ExecuteC()

	if err != nil {
		fmt.Printf("Error executing desync command: %v\n", err)
		return 2
	}
	return 0
}

var (
	tracerProvider *sdktrace.TracerProvider
	tracer         trace.Tracer
	mu             sync.Mutex
	spans          = make(map[uuid.UUID]trace.Span)
	contexts       = make(map[uuid.UUID]context.Context)
	nextID         int64
)

//export InitTracerProvider
func InitTracerProvider(name *C.char, host *C.char, jsonString *C.char, token *C.char) *C.char {

	ctx := context.Background()

	traceExporter, err := otlptracehttp.New(
		ctx,
		otlptracehttp.WithEndpoint(C.GoString(host)),
		otlptracehttp.WithHeaders(map[string]string{"Authorization": C.GoString(token)}),
	)

	if err != nil {
		log.Fatal(err)
	}
	var data map[string]interface{}
	err = json.Unmarshal([]byte(C.GoString(jsonString)), &data)
	if err != nil {
		return C.CString(fmt.Sprintf("Failed to decode JSON: %v", err))
	}

	attrs := make([]attribute.KeyValue, 0, len(data))
	for k, v := range data {
		strVal, ok := v.(string)
		if !ok {
			strVal = fmt.Sprintf("%v", v)
		}
		attrs = append(attrs, attribute.String(k, strVal))
	}

	attrs = append(attrs, semconv.ServiceNameKey.String(C.GoString(name)))

	res, err := resource.New(ctx, resource.WithAttributes(attrs...))
	if err != nil {
		return C.CString(fmt.Sprintf("Could not set resources: %v", err))
	}

	if err != nil {
		log.Fatal(err)
	}

	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(traceExporter),
	)

	otel.SetTracerProvider(tracerProvider)
	tracer = tracerProvider.Tracer(C.GoString(name))
	otel.SetTextMapPropagator(propagation.TraceContext{})
	return nil
}

//export StartSpan
func StartSpan(name *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()

	if tracer == nil {
		return C.CString("00000000-0000-0000-0000-000000000000")
	}

	ctx := context.Background()
	_, span := tracer.Start(ctx, C.GoString(name))

	id := uuid.New()
	spans[id] = span

	return C.CString(id.String())
}

//export StartSpanWithParent
func StartSpanWithParent(name *C.char, parentID *C.char) *C.char {
	parentUUID, err := uuid.Parse(C.GoString(parentID))
	if err != nil {
		return C.CString("00000000-0000-0000-0000-000000000000")
	}

	mu.Lock()
	parentSpan, ok := spans[parentUUID]
	mu.Unlock()

	if !ok {
		return C.CString("00000000-0000-0000-0000-000000000000")
	}

	ctx := trace.ContextWithSpan(context.Background(), parentSpan)
	_, span := tracer.Start(ctx, C.GoString(name))

	mu.Lock()
	id := uuid.New()
	spans[id] = span
	mu.Unlock()

	return C.CString(id.String())
}

//export AddEvent
func AddEvent(id *C.char, name *C.char) {
	uuidID, err := uuid.Parse(C.GoString(id))
	if err != nil || uuidID == uuid.Nil {
		return
	}

	mu.Lock()
	span := spans[uuidID]
	mu.Unlock()
	span.AddEvent(C.GoString(name))
}

//export SetAttributes
func SetAttributes(id *C.char, jsonStr *C.char) {
	uuidID, err := uuid.Parse(C.GoString(id))
	if err != nil || uuidID == uuid.Nil {
		return
	}

	mu.Lock()
	span := spans[uuidID]
	mu.Unlock()

	var data map[string]interface{}
	err = json.Unmarshal([]byte(C.GoString(jsonStr)), &data)
	if err != nil {
		log.Printf("Invalid JSON: %s", C.GoString(jsonStr))
		return
	}

	for k, v := range data {
		strVal, ok := v.(string)
		if !ok {
			strVal = fmt.Sprintf("%v", v)
		}
		attribute := attribute.String(k, strVal)
		span.SetAttributes(attribute)
	}
}

//export RecordError
func RecordError(id *C.char, err *C.char) {
	uuidID, parseErr := uuid.Parse(C.GoString(id))
	if parseErr != nil || uuidID == uuid.Nil {
		return
	}

	mu.Lock()
	span := spans[uuidID]
	mu.Unlock()
	errGo := C.GoString(err)
	span.RecordError(errors.New(errGo))
	span.SetStatus(codes.Error, errGo)
}

//export EndSpan
func EndSpan(id *C.char) {
	uuidID, err := uuid.Parse(C.GoString(id))
	if err != nil || uuidID == uuid.Nil {
		return
	}

	mu.Lock()
	span := spans[uuidID]
	delete(spans, uuidID)
	mu.Unlock()
	span.End()
}

//export Shutdown
func Shutdown() *C.char {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err := tracerProvider.Shutdown(ctx)
	if err != nil {
		return C.CString(err.Error())
	}

	return nil
}

//export DeleteContext
func DeleteContext(id *C.char) {
	uuidID, err := uuid.Parse(C.GoString(id))
	if err != nil {
		return
	}

	mu.Lock()
	delete(contexts, uuidID)
	mu.Unlock()
}
