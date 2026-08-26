package com.cloudnativeapi.observability.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestLoggingFilter extends OncePerRequestFilter {

	static final String REQUEST_ID_HEADER = "X-Request-ID";
	static final String REQUEST_ID_MDC_KEY = "request_id";
	static final String HTTP_METHOD_MDC_KEY = "http_method";
	static final String HTTP_PATH_MDC_KEY = "http_path";

	private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);
	private static final Pattern SAFE_REQUEST_ID = Pattern.compile("[A-Za-z0-9._-]{1,128}");
	private static final Set<String> INTERNAL_PROBE_PATHS = Set.of(
		"/actuator/health/liveness",
		"/actuator/health/readiness"
	);

	@Override
	protected void doFilterInternal(
		HttpServletRequest request,
		HttpServletResponse response,
		FilterChain filterChain
	) throws ServletException, IOException {
		var requestId = resolveRequestId(request.getHeader(REQUEST_ID_HEADER));
		var startedAtNanos = System.nanoTime();

		response.setHeader(REQUEST_ID_HEADER, requestId);
		MDC.put(REQUEST_ID_MDC_KEY, requestId);
		MDC.put(HTTP_METHOD_MDC_KEY, request.getMethod());
		MDC.put(HTTP_PATH_MDC_KEY, request.getRequestURI());

		var completionStatus = HttpServletResponse.SC_INTERNAL_SERVER_ERROR;

		try {
			filterChain.doFilter(request, response);
			completionStatus = response.getStatus();
		} finally {
			var durationMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAtNanos);

			try {
				if (shouldLogCompletion(request.getRequestURI(), completionStatus)) {
					logCompletion(completionStatus, durationMillis);
				}
			} finally {
				MDC.remove(REQUEST_ID_MDC_KEY);
				MDC.remove(HTTP_METHOD_MDC_KEY);
				MDC.remove(HTTP_PATH_MDC_KEY);
			}
		}
	}

	private static String resolveRequestId(String candidate) {
		if (candidate != null && SAFE_REQUEST_ID.matcher(candidate).matches()) {
			return candidate;
		}

		return UUID.randomUUID().toString();
	}

	private static boolean shouldLogCompletion(String path, int status) {
		return status >= 400 || !INTERNAL_PROBE_PATHS.contains(path);
	}

	private static void logCompletion(int status, long durationMillis) {
		var eventBuilder = status >= 500
			? log.atError()
			: status >= 400 ? log.atWarn() : log.atInfo();

		eventBuilder
			.addKeyValue("event", "http_request_completed")
			.addKeyValue("http_status", status)
			.addKeyValue("duration_ms", durationMillis)
			.log("HTTP request completed");
	}
}
