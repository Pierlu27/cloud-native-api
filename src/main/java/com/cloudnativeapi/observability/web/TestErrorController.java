package com.cloudnativeapi.observability.web;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/observability")
@ConditionalOnProperty(prefix = "observability.test-error", name = "enabled", havingValue = "true")
public class TestErrorController {

	@PostMapping("/test-error")
	public void triggerTestError() {
		throw new IllegalStateException("Controlled observability test error");
	}

}
