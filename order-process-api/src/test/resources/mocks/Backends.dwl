%dw 2.0

// Answers for the HTTP stub that stands in for both system APIs. The Opportunity ID picks the
// scenario, so each test only has to choose an ID.
var HAPPY = "006000000000001AAA"
var EXISTING_CUSTOMER = "006000000000002AAA"
var DUPLICATE = "006000000000003AAA"
var ERP_REJECTS = "006000000000004AAA"
var ERP_DOWN = "006000000000005AAA"

fun opportunity(id) = {
    id: id,
    name: "Test Opportunity",
    stage: "Closed Won",
    accountId: "acct-" ++ id,
    accountName: "Test Customer",
    erpOrderId: null,
    erpStatus: null,
    lineItems: [{ productCode: "WIDGET-100", quantity: 2, unitPrice: 100 }]
}

fun opportunityIdFrom(path, query, body) =
    if (path startsWith "/api/opportunities/") (path splitBy "/")[-1]
    else if (query.sfOpportunityId != null) query.sfOpportunityId
    else if (query.sfAccountId != null) query.sfAccountId replace "acct-" with ""
    else body.sfOpportunityId default ""

fun status(method, path, query, body) = do {
    var id = opportunityIdFrom(path, query, body)
    ---
    if (path startsWith "/api/opportunities/") (if (method == "PATCH") 204 else 200)
    else if (id == ERP_DOWN) 503
    else if (method == "GET") 200
    else if (path == "/api/sales-orders" and id == ERP_REJECTS) 422
    else 201
}

fun respond(method, path, query, body) = do {
    var id = opportunityIdFrom(path, query, body)
    ---
    if (path startsWith "/api/opportunities/") (if (method == "GET") opportunity(id) else {})
    else if (id == ERP_DOWN) { code: "UNAVAILABLE", message: "ERP is down" }
    else if (method == "GET" and path == "/api/sales-orders")
        (if (id == DUPLICATE) [{ id: "SO-EXISTING", status: "To Deliver and Bill" }] else [])
    else if (method == "GET" and path == "/api/customers")
        (if (id == EXISTING_CUSTOMER) [{ id: "EXISTING-CUSTOMER", name: "Test Customer" }] else [])
    else if (path == "/api/customers") { id: "NEW-CUSTOMER", name: "Test Customer" }
    else if (id == ERP_REJECTS) { code: "REJECTED", message: "Could not find Item Code: WIDGET-100" }
    else { id: "SO-NEW", status: "To Deliver and Bill" }
}
