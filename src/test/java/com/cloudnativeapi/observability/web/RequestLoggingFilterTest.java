package com.cloudnativeapi.observability.web;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import jakarta.servlet.ServletException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RequestLoggingFilterTest {

	private final RequestLoggingFilter filter = new RequestLoggingFilter();
	private final Logger filterLogger = (Logger) LoggerFactory.getLogger(RequestLoggingFilter.class);
	private ListAppender<ILoggingEvent> logAppender;

	@BeforeEach
	void attachLogAppender() {
		logAppender = new ListAppender<>();
		logAppender.start();
		filterLogger.addAppender(logAppender);
	}

	@AfterEach
	void detachLogAppenderAndClearMdc() {
		filterLogger.detachAppender(logAppender);
		logAppender.stop();
		MDC.clear();
	}

	@Test
	void preservesValidRequestIdAndMakesContextAvailableDuringRequest() throws Exception {
		var request = new MockHttpServletRequest("GET", "/api/jobs");
		request.setQueryString("token=must-not-be-logged");
		request.addHeader(RequestLoggingFilter.REQUEST_ID_HEADER, "client-request_123");
		var response = new MockHttpServletResponse();
		var contextDuringRequest = new AtomicReference<Map<String, String>>();

		filter.doFilter(request, response, (servletRequest, servletResponse) -> {
			contextDuringRequest.set(MDC.getCopyOfContextMap());
			((MockHttpServletResponse) servletResponse).setStatus(201);
		});

		assertThat(response.getHeader(RequestLoggingFilter.REQUEST_ID_HEADER))
			.isEqualTo("client-request_123");
		assertThat(contextDuringRequest.get())
			.containsEntry(RequestLoggingFilter.REQUEST_ID_MDC_KEY, "client-request_123")
			.containsEntry(RequestLoggingFilter.HTTP_METHOD_MDC_KEY, "GET")
			.containsEntry(RequestLoggingFilter.HTTP_PATH_MDC_KEY, "/api/jobs");
		assertMdcWasCleared();

		var event = onlyLogEvent();
		assertThat(event.getLevel()).isEqualTo(Level.INFO);
		assertThat(event.getMDCPropertyMap())
			.containsEntry(RequestLoggingFilter.REQUEST_ID_MDC_KEY, "client-request_123")
			.containsEntry(RequestLoggingFilter.HTTP_METHOD_MDC_KEY, "GET")
			.containsEntry(RequestLoggingFilter.HTTP_PATH_MDC_KEY, "/api/jobs");
		assertThat(keyValue(event, "event")).isEqualTo("http_request_completed");
		assertThat(keyValue(event, "http_status")).isEqualTo(201);
		assertThat((Long) keyValue(event, "duration_ms")).isGreaterThanOrEqualTo(0L);
	}

	@Test
	void replacesUnsafeRequestIdWithUuid() throws Exception {
		var request = new MockHttpServletRequest("GET", "/api/jobs");
		request.addHeader(RequestLoggingFilter.REQUEST_ID_HEADER, "unsafe request id");
		var response = new MockHttpServletResponse();
		var requestIdDuringRequest = new AtomicReference<String>();

		filter.doFilter(request, response, (servletRequest, servletResponse) ->
			requestIdDuringRequest.set(MDC.get(RequestLoggingFilter.REQUEST_ID_MDC_KEY))
		);

		var generatedRequestId = response.getHeader(RequestLoggingFilter.REQUEST_ID_HEADER);
		assertThat(generatedRequestId)
			.isNotEqualTo("unsafe request id")
			.isEqualTo(requestIdDuringRequest.get());
		assertThatCode(() -> UUID.fromString(generatedRequestId)).doesNotThrowAnyException();
		assertMdcWasCleared();
	}

	@Test
	void suppressesSuccessfulInternalProbeCompletionLog() throws Exception {
		var request = new MockHttpServletRequest("GET", "/actuator/health/readiness");
		var response = new MockHttpServletResponse();

		filter.doFilter(request, response, (servletRequest, servletResponse) ->
			((MockHttpServletResponse) servletResponse).setStatus(200)
		);

		assertThat(logAppender.list).isEmpty();
		assertMdcWasCleared();
	}

	@Test
	void logsFailedInternalProbe() throws Exception {
		var request = new MockHttpServletRequest("GET", "/actuator/health/liveness");
		var response = new MockHttpServletResponse();

		filter.doFilter(request, response, (servletRequest, servletResponse) ->
			((MockHttpServletResponse) servletResponse).setStatus(503)
		);

		var event = onlyLogEvent();
		assertThat(event.getLevel()).isEqualTo(Level.ERROR);
		assertThat(keyValue(event, "http_status")).isEqualTo(503);
		assertMdcWasCleared();
	}

	@Test
	void logsPropagatedExceptionAsServerErrorAndClearsMdc() {
		var request = new MockHttpServletRequest("GET", "/api/jobs");
		var response = new MockHttpServletResponse();

		assertThatThrownBy(() -> filter.doFilter(request, response, (servletRequest, servletResponse) -> {
			throw new ServletException("controlled test exception");
		}))
			.isInstanceOf(ServletException.class)
			.hasMessage("controlled test exception");

		var event = onlyLogEvent();
		assertThat(event.getLevel()).isEqualTo(Level.ERROR);
		assertThat(keyValue(event, "http_status")).isEqualTo(500);
		assertMdcWasCleared();
	}

	private ILoggingEvent onlyLogEvent() {
		assertThat(logAppender.list).hasSize(1);
		return logAppender.list.getFirst();
	}

	private static Object keyValue(ILoggingEvent event, String key) {
		return event.getKeyValuePairs().stream()
			.filter(pair -> pair.key.equals(key))
			.map(pair -> pair.value)
			.findFirst()
			.orElseThrow();
	}

	private static void assertMdcWasCleared() {
		assertThat(MDC.get(RequestLoggingFilter.REQUEST_ID_MDC_KEY)).isNull();
		assertThat(MDC.get(RequestLoggingFilter.HTTP_METHOD_MDC_KEY)).isNull();
		assertThat(MDC.get(RequestLoggingFilter.HTTP_PATH_MDC_KEY)).isNull();
	}
}
