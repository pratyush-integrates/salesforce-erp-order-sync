%dw 2.0

// ERP filter syntax: [["field", "=", "value"]]
fun byField(field, value) = { filters: write([[field, "=", value]], "application/json", { indent: false }) }

fun toCustomer(c) = {
    id: c.name,
    name: c.customer_name,
    sfAccountId: c.custom_sf_account_id
}

fun toErpCustomer(c) = {
    customer_name: c.name,
    customer_type: "Company",
    custom_sf_account_id: c.sfAccountId
}

fun toSalesOrder(o) = {
    id: o.name,
    customerId: o.customer,
    sfOpportunityId: o.custom_sf_opportunity_id,
    orderDate: o.transaction_date,
    deliveryDate: o.delivery_date,
    status: o.status,
    total: o.grand_total,
    items: (o.items default []) map {
        itemCode: $.item_code,
        quantity: $.qty,
        unitPrice: $.rate
    }
}

fun toErpSalesOrder(o, company) = {
    customer: o.customerId,
    company: company,
    transaction_date: o.orderDate,
    delivery_date: o.deliveryDate,
    custom_sf_opportunity_id: o.sfOpportunityId,
    items: o.items map {
        item_code: $.itemCode,
        qty: $.quantity,
        rate: $.unitPrice
    }
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
        "ERP:DUPLICATE": 409,
        "ERP:REJECTED": 422,
        "ERP:NOT_FOUND": 404,
        "ERP:UNAVAILABLE": 503,
        "HTTP:CONNECTIVITY": 503,
        "HTTP:TIMEOUT": 503
    }[key] default 500
}
