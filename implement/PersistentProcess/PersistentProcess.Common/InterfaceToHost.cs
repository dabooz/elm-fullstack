﻿using System;

namespace Kalmit.PersistentProcess.InterfaceToHost
{
    public class AppEventStructure
    {
        public ArrivedAtTimeEventStructure ArrivedAtTimeEvent;

        public HttpRequestEvent HttpRequestEvent;

        public ResultFromTaskWithId TaskCompleteEvent;
    }

    public class ResponseOverSerialInterface
    {
        public string DecodeEventError;

        public AppEventResponseStructure DecodeEventSuccess;
    }

    public class AppEventResponseStructure
    {
        public NotifyWhenArrivedAtTimeRequestStructure notifyWhenArrivedAtTime;

        public StartTask[] startTasks;

        public HttpResponseRequest[] completeHttpResponses;
    }

    public class HttpRequestEvent
    {
        public Int64 posixTimeMilli;

        public string httpRequestId;

        public HttpRequestContext requestContext;

        public HttpRequest request;
    }

    public class HttpRequestContext
    {
        public string clientAddress;
    }

    public class HttpRequest
    {
        public string method;

        public string uri;

        public string bodyAsBase64;

        public HttpHeader[] headers;
    }

    public class HttpHeader
    {
        public string name;

        public string[] values;
    }

    public class HttpResponseRequest
    {
        public string httpRequestId;

        public HttpResponse response;
    }

    public class HttpResponse
    {
        public int statusCode;

        public string bodyAsBase64;

        public HttpHeader[] headersToAdd;
    }

    public class ArrivedAtTimeEventStructure
    {
        public Int64 posixTimeMilli;
    }

    public class NotifyWhenArrivedAtTimeRequestStructure
    {
        public Int64 posixTimeMilli;
    }

    public class Result<ErrT, OkT>
    {
        public ErrT Err;

        public OkT Ok;
    }

    public class ResultFromTaskWithId
    {
        public string taskId;

        public TaskResult taskResult;
    }

    public class TaskResult
    {
        public Result<CreateVolatileHostErrorStructure, CreateVolatileHostComplete> CreateVolatileHostResponse;

        public Result<RequestToVolatileHostError, RequestToVolatileHostComplete> RequestToVolatileHostResponse;

        public object CompleteWithoutResult;

        public class CreateVolatileHostErrorStructure
        {
            public string exceptionToString;
        }

        public class CreateVolatileHostComplete
        {
            public string hostId;
        }

        public class RequestToVolatileHostError
        {
            public object HostNotFound;
        }

        public class RequestToVolatileHostComplete
        {
            public string exceptionToString;

            public string returnValueToString;

            public long durationInMilliseconds;
        }
    }

    public class StartTask
    {
        public string taskId;

        public Task task;
    }

    public class Task
    {
        public CreateVolatileHostStructure CreateVolatileHost;

        public RequestToVolatileHostStructure RequestToVolatileHost;

        public ReleaseVolatileHostStructure ReleaseVolatileHost;

        public class CreateVolatileHostStructure
        {
            public string script;
        }

        public class RequestToVolatileHostStructure
        {
            public string hostId;

            public string request;
        }

        public class ReleaseVolatileHostStructure
        {
            public string hostId;
        }
    }
}
