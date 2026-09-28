# Auto-generated tenant table — regenerate and reload Varnish whenever
# a customer is onboarded, changes plan, or is removed. Keep this file
# separate from default.vcl so tooling can template/rewrite just this
# part without touching core logic.
#
# X-Tenant-Origin  : the customer's own image storage origin. This is
#                    the ONLY source imgproxy will ever fetch from for
#                    that tenant — customers cannot point requests at
#                    an arbitrary host.
# X-Tenant-MaxDim  : plan-based ceiling on requested width/height.
# X-Tenant-MaxRPS  : plan-based rate limit (see rate-limiting note in
#                    default.vcl / README).

sub tenant_lookup {
    if (req.http.X-Tenant-Id == "acme") {
        # For local testing this points at the "origin" service defined
        # in docker-compose.yml (a plain static file server). Swap this
        # for the customer's real image storage host in production.
        set req.http.X-Tenant-Origin = "http://origin:80";
        set req.http.X-Tenant-MaxDim = "2048";
        set req.http.X-Tenant-MaxRPS = "50";
    } elsif (req.http.X-Tenant-Id == "globex") {
        set req.http.X-Tenant-Origin = "https://static.globex.io";
        set req.http.X-Tenant-MaxDim = "4096";
        set req.http.X-Tenant-MaxRPS = "200";
    } else {
        # Unknown tenant — vcl_recv turns this into a 404.
        set req.http.X-Tenant-Origin = "";
        set req.http.X-Tenant-MaxDim = "0";
        set req.http.X-Tenant-MaxRPS = "0";
    }
}
