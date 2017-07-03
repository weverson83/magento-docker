# This is a basic VCL configuration file for PageCache powered by Varnish for Magento module.

# default backend definition.  Set this to point to your content server.
backend default {
  .host = "127.0.0.1";
  .port = "80";
  .connect_timeout = 90s;
  .first_byte_timeout = 90s;
  .between_bytes_timeout = 90s;
}

# admin backend with longer timeout values. Set this to the same IP & port as your default server.
backend admin {
  .host = "127.0.0.1";
  .port = "80";
  .first_byte_timeout = 18000s;
  .between_bytes_timeout = 18000s;
}

# add your Magento server IP to allow purges from the backend
acl purge {
  "localhost";
  "127.0.0.1";
  "10.225.0.0"/16;
}

import std;

sub vcl_recv {
    if (req.restarts == 0) {
        if (req.http.x-forwarded-for) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    if (req.request != "GET" &&
        req.request != "HEAD" &&
        req.request != "PUT" &&
        req.request != "POST" &&
        req.request != "TRACE" &&
        req.request != "OPTIONS" &&
        req.request != "DELETE" &&
        req.request != "PURGE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    # purge request
    if (req.request == "PURGE") {
        if (!client.ip ~ purge) {
            error 405 "Not allowed.";
        }
        ban("obj.http.X-Purge-Host ~ " + req.http.X-Purge-Host + " && obj.http.X-Purge-URL ~ " + req.http.X-Purge-Regex + " && obj.http.Content-Type ~ " + req.http.X-Purge-Content-Type);
        error 200 "Purged.";
    }


    if (req.http.CloudFront-Is-Mobile-Viewer == "true") {
        set req.http.X-UA-Device = "iPhone";
    }

    # Redirect Mobile
    if (req.http.CloudFront-Is-Mobile-Viewer == "true" && req.http.host ~ "^qa\.sephora\.com\.br" && req.url !~ "^/(checkout|sample|beautyclub|firecheckout|customer|sales|fale-conosco|novarnish|bseller|esmart|brindes|instashop|review)") {

	set req.http.x-redir =  "http://msephoravalid.neemu.com" + req.url;
        error 850 "Moved Permanently";
    }

    # switch to admin backend configuration
    if (req.http.cookie ~ "adminhtml=") {
        set req.backend = admin;
    }

    # tell backend that esi is supported
    set req.http.X-ESI-Capability = "on";

    # we only deal with GET and HEAD by default
    if (req.request != "GET" && req.request != "HEAD") {
        return (pass);
    }

    # normalize url in case of leading HTTP scheme and domain
    set req.url = regsub(req.url, "^http[s]?://[^/]+", "");

    # collect all cookies
    std.collect(req.http.Cookie);

    # static files are always cacheable. remove SSL flag and cookie
    if (req.url ~ "^/(media|js|skin)/.*\.(png|jpg|jpeg|gif|css|js|swf|ico)$") {
        unset req.http.Https;
        unset req.http.Cookie;
    }

    # formkey lookup
    if (req.url ~ "/varnishcache/getformkey/") {
        # check for formkey in cookie
        if (req.http.Cookie ~ "PAGECACHE_FORMKEY") {
            set req.http.X-Pagecache-Formkey = regsub(req.http.cookie, ".*PAGECACHE_FORMKEY=([^;]*)(;*.*)?", "\1");
        } else {
            # create formkey once
            set req.http.X-Pagecache-Formkey-Raw = req.http.Cookie + client.ip + req.xid;
            C{
                char *result = generate_formkey(VRT_GetHdr(sp, HDR_REQ, "\030X-Pagecache-Formkey-Raw:"));
                VRT_SetHdr(sp, HDR_REQ, "\024X-Pagecache-Formkey:", result, vrt_magic_string_end);
            }C
        }
        unset req.http.X-Pagecache-Formkey-Raw;
        error 760 req.http.X-Pagecache-Formkey;
    }

    # do not cache any page from index files
    if (req.url ~ "^/(index)") {
        return (pass);
    }

    # as soon as we have a NO_CACHE cookie pass request
    if (req.http.cookie ~ "NO_CACHE=") {
        return (pass);
    }

    # normalize Accept-Encoding header
    # http://varnish.projects.linpro.no/wiki/FAQ/Compression
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|flv)$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate" && req.http.user-agent !~ "MSIE") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm
            remove req.http.Accept-Encoding;
        }
    }

    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl|zanpid|btg_source|idparceria|ranking|utm_term|id|page|idproduto|iddepartamento|idcategoria|idsubcategoria|idmarca|_|acao|a_aid|undefined|timestamp|idProduto|nm_origem|nm_beautyboard_sku|nm_ranking_rec)=") {
      set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl|zanpid|btg_source|idparceria|ranking|utm_term|id|page|idproduto|iddepartamento|idcategoria|idsubcategoria|idmarca|_|acao|a_aid|undefined|timestamp|idProduto|nm_origem|nm_beautyboard_sku|nm_ranking_rec)=([A-z0-9_\-\.%25]+)", "");
      set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl|zanpid|btg_source|idparceria|ranking|utm_term|id|page|idproduto|iddepartamento|idcategoria|idsubcategoria|idmarca|_|acao|a_aid|undefined|timestamp|idProduto|nm_origem|nm_beautyboard_sku|nm_ranking_rec)=([A-z0-9_\-\.%25]+)", "?");
      set req.url = regsub(req.url, "\?&", "?");
      set req.url = regsub(req.url, "\?$", "");
    }

    if (req.url ~ "\#") {
      set req.url = regsub(req.url, "\#.*$", "");
    }

    if (req.url ~ "\?$") {
      set req.url = regsub(req.url, "\?$", "");
    }

    return (lookup);
}

# sub vcl_pipe {
#     # Note that only the first request to the backend will have
#     # X-Forwarded-For set.  If you use X-Forwarded-For and want to
#     # have it set for all requests, make sure to have:
#     # set bereq.http.connection = "close";
#     # here.  It is not set by default as it might break some broken web
#     # applications, like IIS with NTLM authentication.
#     return (pipe);
# }

# sub vcl_pass {
#     return (pass);
# }

sub vcl_hash {
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }

    if (req.http.cookie ~ "PAGECACHE_ENV=") {
        set req.http.pageCacheEnv = regsub(
            req.http.cookie,
            "(.*)PAGECACHE_ENV=([^;]*)(.*)",
            "\2"
        );
        hash_data(req.http.pageCacheEnv);
        remove req.http.pageCacheEnv;
    }


###  TESTE MOBILE CDN USER-AGENT FIX ### Quierati
    if (req.http.CloudFront-Is-Mobile-Viewer) {
	hash_data(req.http.CloudFront-Is-Mobile-Viewer);
    }
###

    if (!(req.url ~ "^/(media|js|skin)/.*\.(png|jpg|jpeg|gif|css|js|swf|ico)$")) {
        call design_exception;
    }
    return (hash);
}

# sub vcl_hit {
#     return (deliver);
# }

# sub vcl_miss {
#     return (fetch);
# }
### TESTE MOBILE FIX USER-AGENT # Quierati
sub vcl_miss { if (req.http.X-UA-Device) { set bereq.http.User-Agent = req.http.X-UA-Device; } }
sub vcl_pass { if (req.http.X-UA-Device) { set bereq.http.User-Agent = req.http.X-UA-Device; } }
###

sub vcl_fetch {
    if (beresp.status >= 500) {
       # let SOAP errors pass - better debugging
      if ((beresp.http.Content-Type ~ "text/xml") || (req.url ~ "^/errors/")) {
           return (deliver);
       }
       set beresp.saintmode = 10s;
       return (restart);
    }
    set beresp.grace = 5m;

    # enable ESI feature
    set beresp.do_esi = true;

    # add ban-lurker tags to object
    set beresp.http.X-Purge-URL  = req.url;
    set beresp.http.X-Purge-Host = req.http.host;

    if (beresp.status == 200 || beresp.status == 301 || beresp.status == 404) {
        if (beresp.http.Content-Type ~ "text/html" || beresp.http.Content-Type ~ "text/xml") {
            if ((beresp.http.Set-Cookie ~ "NO_CACHE=") || (beresp.ttl < 1s)) {
                set beresp.ttl = 0s;
                set beresp.http.Enable-Cache-Control = "1";
                return (hit_for_pass);
            }

            # marker for vcl_deliver to reset Age:
            set beresp.http.magicmarker = "1";

            # Don't cache cookies
            unset beresp.http.set-cookie;
        } else {
            # set default TTL value for static content
            set beresp.ttl = 4h;
        }
        return (deliver);
    }
    set beresp.http.Enable-Cache-Control = "1";
    return (hit_for_pass);
}

sub vcl_deliver {
    # debug info
    if (resp.http.X-Cache-Debug) {
        if (obj.hits > 0) {
            set resp.http.X-Cache      = "HIT";
            set resp.http.X-Cache-Hits = obj.hits;
        } else {
            set resp.http.X-Cache      = "MISS";
        }
        set resp.http.X-Cache-Expires  = resp.http.Expires;
    } else {
        # remove Varnish/proxy header
        remove resp.http.X-Varnish;
        remove resp.http.Via;
        remove resp.http.Age;
        remove resp.http.X-Purge-URL;
        remove resp.http.X-Purge-Host;
    }

    if (resp.http.magicmarker) {
        # Remove the magic marker
        unset resp.http.magicmarker;

        #set resp.http.Cache-Control = "no-store, no-cache, must-revalidate, post-check=0, pre-check=0";
        #set resp.http.Pragma        = "no-cache";
        #set resp.http.Expires       = "Mon, 31 Mar 2008 10:00:00 GMT";
        #set resp.http.Age           = "0";
        remove resp.http.Expires;
	remove resp.http.Cache-Control;
    	remove resp.http.Pragma;


    }
    remove resp.http.Age;
    remove resp.http.Server;


    if (resp.http.Enable-Cache-Control) {
        unset resp.http.Enable-Cache-Control;
        set resp.http.Cache-Control = "no-store, no-cache, must-revalidate, post-check=0, pre-check=0";
        set resp.http.Pragma        = "no-cache";
        set resp.http.Expires       = "Mon, 31 Mar 2008 10:00:00 GMT";
        set resp.http.Age           = "0";
    }


}

sub vcl_error {

    # workaround for possible security issue
    if (req.url ~ "^\s") {
        set obj.status = 400;
        set obj.response = "Malformed request";
        synthetic "";
        return(deliver);
    }

    # formkey request
    if (obj.status == 760) {
        set obj.status = 200;
	    synthetic obj.response;
        return(deliver);
    }

    # redirect mobile
    if (obj.status == 850) {
        set obj.http.Location = req.http.x-redir;
        set obj.status = 301;
        return (deliver);
    }

    # error 200
    if (obj.status == 200) {
        return (deliver);
    }
    remove obj.http.Expires;
    remove obj.http.Cache-Control;
    remove obj.http.Pragma;
    remove obj.http.Age;
    remove obj.http.Server;


     set obj.http.Cache-Control = "no-store, no-cache, must-revalidate, post-check=0, pre-check=0";
     set obj.http.Content-Type = "text/html; charset=utf-8";
     set obj.http.Retry-After = "5";
     synthetic {"
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
    <head>
        <title>"} + obj.status + " " + obj.response + {"</title>
    </head>
    <body>
        <h1>Error "} + obj.status + " " + obj.response + {"</h1>
        <p>"} + obj.response + {"</p>
        <h3>Guru Meditation:</h3>
        <p>XID: "} + req.xid + {"</p>
        <hr>
        <p>Varnish cache server</p>
    </body>
</html>
"};
     return (deliver);
}


# sub vcl_fini {
#   return (ok);
# }

sub design_exception {
}

C{
    #include <string.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <openssl/md5.h>

    /**
     * create md5 hash of string and return it
     */
    char *generate_formkey(char *string) {
        // generate md5
        unsigned char result[MD5_DIGEST_LENGTH];
        MD5((const unsigned char *)string, strlen(string), result);

        // convert to chars
        static char md5string[MD5_DIGEST_LENGTH + 1];
        const char *hex = "0123456789ABCDEF";
        unsigned char *pin = result;
        char *pout = md5string;

        for(; pin < result + sizeof(result); pout+=2, pin++) {
            pout[0] = hex[(*pin>>4) & 0xF];
            pout[1] = hex[ *pin     & 0xF];
        }
        pout[-1] = 0;

        // return md5
        return md5string;
    }
}C
