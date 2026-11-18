%dw 2.0

fun failedQuery(since) = {
    status: "Failed",
    (since: since) if (since != null)
}

fun httpStatusFor(namespace, identifier) = do {
    var key = namespace ++ ":" ++ identifier
    ---
    {
        "APIKIT:BAD_REQUEST": 400,
        "APIKIT:NOT_FOUND": 404,
        "APIKIT:METHOD_NOT_ALLOWED": 405,
        "APIKIT:NOT_ACCEPTABLE": 406,
        "APIKIT:NOT_IMPLEMENTED": 501,
        "HTTP:NOT_FOUND": 404,
        "HTTP:BAD_REQUEST": 400,
        "HTTP:CONNECTIVITY": 503,
        "HTTP:TIMEOUT": 503,
        "HTTP:SERVICE_UNAVAILABLE": 503
    }[key] default 500
}
