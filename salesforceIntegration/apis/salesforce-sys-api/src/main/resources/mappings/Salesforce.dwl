%dw 2.0

fun toSoqlDateTime(value) = ((value as DateTime) >> "UTC") as String { format: "yyyy-MM-dd'T'HH:mm:ss'Z'" }

// erpStatus is safe to bind: the spec restricts it to letters and spaces. since is reformatted above.
fun resultsQuery(since) =
    "SELECT Id, Name, ERP_Order_Id__c, ERP_Status__c, ERP_Error__c, ERP_Synced_At__c FROM Opportunity WHERE ERP_Status__c = ':erpStatus'"
    ++ (if (since != null) " AND ERP_Synced_At__c >= :since" else "")
    ++ " ORDER BY ERP_Synced_At__c DESC LIMIT 200"

fun resultsParams(erpStatus, since) = {
    erpStatus: erpStatus,
    (since: toSoqlDateTime(since)) if (since != null)
}

fun toErpResult(r) = {
    opportunityId: r.Id,
    opportunityName: r.Name,
    erpOrderId: r.ERP_Order_Id__c,
    erpStatus: r.ERP_Status__c,
    erpError: r.ERP_Error__c,
    syncedAt: r.ERP_Synced_At__c
}

fun toOpportunity(r) = do {
    // A nested SOQL query can come back as a list or wrapped in { records: [...] }.
    var lines = r.OpportunityLineItems.records default r.OpportunityLineItems default []
    ---
    {
        id: r.Id,
        name: r.Name,
        stage: r.StageName,
        accountId: r.AccountId,
        accountName: r.Account.Name,
        erpOrderId: r.ERP_Order_Id__c,
        erpStatus: r.ERP_Status__c,
        erpError: r.ERP_Error__c,
        syncedAt: r.ERP_Synced_At__c,
        lineItems: lines map {
            productCode: $.ProductCode,
            quantity: $.Quantity as Number,
            unitPrice: $.UnitPrice as Number
        }
    }
}

// Leaves ERP_Order_Id__c alone when no order number is sent, so a failed replay keeps the old one.
fun toUpdateRecord(id, update, syncedAt) = {
    Id: id,
    ERP_Status__c: update.erpStatus,
    ERP_Synced_At__c: syncedAt,
    (ERP_Order_Id__c: update.erpOrderId) if (update.erpOrderId != null),
    (ERP_Error__c: update.erpError) if (update.erpError != null),
    (fieldsToNull: ["ERP_Error__c"]) if (update.erpError == null)
}

fun httpStatusFor(namespace, identifier) = do {
    var key = namespace ++ ":" ++ identifier
    ---
    if (namespace == "SALESFORCE") 503
    else {
        "APIKIT:BAD_REQUEST": 400,
        "APIKIT:NOT_FOUND": 404,
        "APIKIT:METHOD_NOT_ALLOWED": 405,
        "APIKIT:NOT_ACCEPTABLE": 406,
        "APIKIT:UNSUPPORTED_MEDIA_TYPE": 415,
        "APIKIT:NOT_IMPLEMENTED": 501,
        "SF:NOT_FOUND": 404,
        "SF:UPDATE_FAILED": 422
    }[key] default 500
}
