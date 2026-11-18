%dw 2.0

fun validationError(o) =
    if (o.stage != "Closed Won") "Opportunity is not Closed Won"
    else if (o.accountId == null) "Opportunity has no Account"
    else if (isEmpty(o.lineItems default [])) "Opportunity has no line items"
    else if (sizeOf(o.lineItems filter (($.productCode default "") == "")) > 0) "A line item has no Product Code"
    else null

// Order date is today, not CloseDate: ERPNext rejects a date in a closed fiscal year.
fun toNewSalesOrder(o, customerId, today, leadDays) = {
    customerId: customerId,
    sfOpportunityId: o.id,
    orderDate: today,
    deliveryDate: today + ("P$(leadDays)D" as Period),
    items: o.lineItems map {
        itemCode: $.productCode,
        quantity: $.quantity,
        unitPrice: $.unitPrice
    }
}

fun successResult(o, order) = {
    opportunityId: o.id,
    opportunityName: o.name,
    erpOrderId: order.id,
    status: order.status,
    error: null,
    syncedAt: now()
}

fun truncate(s, max) = if (sizeOf(s) > max) s[0 to max - 1] else s

fun failureReason(identifier, description) =
    if (identifier == "RETRY_EXHAUSTED") "A downstream system was unavailable after retries"
    else truncate(description default "Unknown error", 255)

fun failureResult(opportunityId, o, reason) = {
    opportunityId: opportunityId,
    opportunityName: o.name,
    erpOrderId: o.erpOrderId,
    status: "Failed",
    error: reason,
    syncedAt: now()
}

fun fromOpportunity(o) = {
    opportunityId: o.id,
    opportunityName: o.name,
    erpOrderId: o.erpOrderId,
    status: o.erpStatus default "Not Synced",
    error: o.erpError,
    syncedAt: o.syncedAt
}

fun fromErpResult(r) = {
    opportunityId: r.opportunityId,
    opportunityName: r.opportunityName,
    erpOrderId: r.erpOrderId,
    status: r.erpStatus,
    error: r.erpError,
    syncedAt: r.syncedAt
}

fun resultsQuery(status, since) = {
    erpStatus: status,
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
        "APIKIT:UNSUPPORTED_MEDIA_TYPE": 415,
        "APIKIT:NOT_IMPLEMENTED": 501,
        "ORDER:NOT_FOUND": 404,
        "ORDER:UPSTREAM": 503,
        "MULE:RETRY_EXHAUSTED": 503
    }[key] default 500
}
