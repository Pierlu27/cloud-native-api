package com.cloudnativeapi.job.web.error;

import com.cloudnativeapi.job.service.JobNotFoundException;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.converter.HttpMessageNotReadableException;

import java.time.Instant;
import java.util.List;

@RestControllerAdvice
public class GlobalExceptionHandler {

	private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

	@ExceptionHandler(JobNotFoundException.class)
	public ResponseEntity<ApiErrorResponse> handleNotFound(JobNotFoundException exception, HttpServletRequest request) {
		log.warn("API request failed with 404: method={} path={} message={}", request.getMethod(), request.getRequestURI(), exception.getMessage());
		return build(HttpStatus.NOT_FOUND, "Job not found: " + exception.getId(), request.getRequestURI(), List.of());
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	public ResponseEntity<ApiErrorResponse> handleValidation(MethodArgumentNotValidException exception, HttpServletRequest request) {
		log.warn("API request failed with 400 validation error: method={} path={}", request.getMethod(), request.getRequestURI());
		var details = exception.getBindingResult().getFieldErrors().stream()
			.map(error -> error.getField() + ": " + error.getDefaultMessage())
			.toList();
		return build(HttpStatus.BAD_REQUEST, "Validation failed", request.getRequestURI(), details);
	}

	@ExceptionHandler({
		IllegalArgumentException.class,
		HttpMessageNotReadableException.class,
		MethodArgumentTypeMismatchException.class
	})
	public ResponseEntity<ApiErrorResponse> handleBadRequest(RuntimeException exception, HttpServletRequest request) {
		log.warn("API request failed with 400: method={} path={} message={}", request.getMethod(), request.getRequestURI(), exception.getMessage());
		return build(HttpStatus.BAD_REQUEST, exception.getMessage(), request.getRequestURI(), List.of());
	}

	@ExceptionHandler(Exception.class)
	public ResponseEntity<ApiErrorResponse> handleUnexpected(Exception exception, HttpServletRequest request) {
		log.error("API request failed with 500: method={} path={}", request.getMethod(), request.getRequestURI(), exception);
		return build(
			HttpStatus.INTERNAL_SERVER_ERROR,
			"An unexpected error occurred",
			request.getRequestURI(),
			List.of()
		);
	}

	private static ResponseEntity<ApiErrorResponse> build(HttpStatus status, String message, String path, List<String> details) {
		var body = new ApiErrorResponse(Instant.now(), status.value(), status.getReasonPhrase(), message, path, details);
		return ResponseEntity.status(status).body(body);
	}
}
