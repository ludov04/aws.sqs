#' @title Execute SQS API Request
#' @description This is the workhorse function to execute calls to the SQS API.
#' @details This function constructs and signs an SQS API request and returns the
#' results thereof, or relevant debugging information in the case of error.
#' 
#' @param url A character string containing an SQS API endpoint URL.
#' @param query An optional named list containing query string parameters and
#' their character values.
#' @param region A character string containing an AWS region. If missing, the
#' default \dQuote{us-east-1} is used.
#' @param key A character string containing an AWS Access Key ID. The default
#' is pulled from environment variable \dQuote{AWS_ACCESS_KEY_ID}.
#' @param secret A character string containing an AWS Secret Access Key. The
#' default is pulled from environment variable \dQuote{AWS_SECRET_ACCESS_KEY}.
#' @param ... Additional arguments passed to \code{\link[httr]{GET}}.
#' @return If successful, a named list. Otherwise, a data structure of class
#' \dQuote{aws_error} containing any error message(s) from AWS and information
#' about the request attempt.
#' @author Thomas J. Leeper
#' @importFrom aws.signature signature_v4_auth
#' @importFrom jsonlite fromJSON
#' @importFrom XML xmlParse xmlToList
#' @import httr
#' @export
sqsHTTP <- function(url = NULL, 
                    query = list(), 
                    region = Sys.getenv("AWS_DEFAULT_REGION", "us-east-1"), 
                    key = Sys.getenv("AWS_ACCESS_KEY_ID"), 
                    secret = Sys.getenv("AWS_SECRET_ACCESS_KEY"), 
                    ...) {
    if (is.null(url)) {
        url <- paste0("https://sqs.",region,".amazonaws.com")
    }
    p <- parse_url
    p <- parse_url(url)
    action <- if(p$path == "") "/" else paste0("/",p$path)
    d_timestamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
    if (key == "") {
        H <- add_headers(`x-amz-date` = d_timestamp)
    } else {
        S <- signature_v4_auth(
               datetime = d_timestamp,
               region = region,
               service = "sqs",
               verb = "GET",
               action = action,
               query_args = query,
               canonical_headers = list(host = paste0("sqs.",region,".amazonaws.com"),
                                        `x-amz-date` = d_timestamp),
               request_body = "",
               key = key, secret = secret)
        H <- add_headers(`x-amz-date` = d_timestamp, 
                         `x-amz-content-sha256` = S$BodyHash,
                         Authorization = S$SignatureHeader)
    }
    
    if (length(query)) {
        r <- GET(url, H, query = query, ...)
    } else {
        r <- GET(url, H, ...)
    }

    cont <- content(r, "text", encoding = "UTF-8")
    if (tolower(http_status(r)$category) == "client error") {
        x <- try(xmlToList(xmlParse(cont)), silent = TRUE)
        if (inherits(x, "try-error")) {
            x <- try(fromJSON(cont)$Error, silent = TRUE)
        }
        warning(paste0(http_status(r)$message, ": ", x$Code, " (", x$Message, ")"))
        h <- headers(r)
        out <- structure(x, headers = h, class = "aws_error")
        attr(out, "request_canonical") <- S$CanonicalRequest
        attr(out, "request_string_to_sign") <- S$StringToSign
        attr(out, "request_signature") <- S$SignatureHeader
    } else {
        out <- try(fromJSON(cont), silent = TRUE)
        if (inherits(out, "try-error")) {
            out2 <- try(xmlToList(xmlParse(cont)), silent = TRUE)
            if (inherits(out2, "try-error")) {
                out <- structure(cont, class = "unknown")
            } else {
                out <- out2
            }
            
        }
    }
    return(out)
}
