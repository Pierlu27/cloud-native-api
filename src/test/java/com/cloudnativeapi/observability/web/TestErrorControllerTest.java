package com.cloudnativeapi.observability.web;

import com.cloudnativeapi.job.web.error.GlobalExceptionHandler;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class TestErrorControllerTest {

	private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
		.withUserConfiguration(TestErrorController.class);

	@Test
	void doesNotRegisterControllerByDefault() {
		contextRunner.run(context -> assertThat(context).doesNotHaveBean(TestErrorController.class));
	}

	@Test
	void registersControllerAndReturns500WhenEnabled() {
		contextRunner
			.withPropertyValues("observability.test-error.enabled=true")
			.run(context -> {
				assertThat(context).hasSingleBean(TestErrorController.class);

				var mockMvc = MockMvcBuilders
					.standaloneSetup(context.getBean(TestErrorController.class))
					.setControllerAdvice(new GlobalExceptionHandler())
					.addFilters(new RequestLoggingFilter())
					.build();

				mockMvc.perform(post("/internal/observability/test-error"))
					.andExpect(status().isInternalServerError())
					.andExpect(header().exists("X-Request-ID"))
					.andExpect(jsonPath("$.status").value(500))
					.andExpect(jsonPath("$.path").value("/internal/observability/test-error"));
			});
	}

}
