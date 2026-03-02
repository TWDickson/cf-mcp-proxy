import OAuthProvider from "@cloudflare/workers-oauth-provider";
import { handleAccessRequest } from "./access-handler";

async function proxyToUpstream(request: Request, env: Env): Promise<Response> {
	const upstream = (env as any).MCP_UPSTREAM_URL as string;

	if (!upstream) {
		return new Response("MCP_UPSTREAM_URL not configured", { status: 500 });
	}

	const hasBody = request.method !== "GET" && request.method !== "HEAD";

	// Copy headers, stripping ones that shouldn't be forwarded
	const headers = new Headers();
	for (const [key, value] of request.headers.entries()) {
		const lower = key.toLowerCase();
		if (lower === "host" || lower === "content-length" || lower === "transfer-encoding") {
			continue;
		}
		headers.set(key, value);
	}

	// Add CF Access service token for tunnel authentication
	headers.set("CF-Access-Client-Id", (env as any).SERVICE_CLIENT_ID as string);
	headers.set("CF-Access-Client-Secret", (env as any).SERVICE_CLIENT_SECRET as string);

	const upstreamRequest = new Request(upstream, {
		method: request.method,
		headers,
		body: hasBody ? request.body : undefined,
		// @ts-ignore - required for streaming bodies in Cloudflare Workers
		duplex: hasBody ? "half" : undefined,
	});

	return fetch(upstreamRequest);
}

export default new OAuthProvider({
	apiHandler: {
		fetch: async (request: Request, env: Env, _ctx: ExecutionContext) => {
			return proxyToUpstream(request, env);
		},
	},
	apiRoute: "/mcp",
	authorizeEndpoint: "/authorize",
	clientRegistrationEndpoint: "/register",
	defaultHandler: { fetch: handleAccessRequest as any },
	tokenEndpoint: "/token",
});
