package com.cloudnativeapi.job.web;

import com.cloudnativeapi.job.repository.JobRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
class JobControllerIntegrationTest {

	@Container
	static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
		.withDatabaseName("cloud_native_api")
		.withUsername("cloud_native_api")
		.withPassword("cloud_native_api");

	@DynamicPropertySource
	static void registerProperties(DynamicPropertyRegistry registry) {
		registry.add("spring.datasource.url", postgres::getJdbcUrl);
		registry.add("spring.datasource.username", postgres::getUsername);
		registry.add("spring.datasource.password", postgres::getPassword);
	}

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private JobRepository jobRepository;

	@BeforeEach
	void clearDatabase() {
		jobRepository.deleteAll();
	}

	@Test
	void createsListsUpdatesAndDeletesJobs() throws Exception {
		var createResponse = mockMvc.perform(post("/api/jobs")
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
					{"title":"Build pipeline","description":"Create the CI pipeline"}
					"""))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.title").value("Build pipeline"))
			.andExpect(jsonPath("$.status").value("PENDING"))
			.andReturn();

		var createdJson = createResponse.getResponse().getContentAsString();
		var id = UUID.fromString(createdJson.replaceAll(".*\"id\":\"([^\"]+)\".*", "$1"));

		mockMvc.perform(get("/api/jobs"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$[0].id").value(id.toString()));

		mockMvc.perform(put("/api/jobs/{id}", id)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
					{"title":"Build pipeline","description":"Release pipeline","status":"RUNNING"}
					"""))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("RUNNING"))
			.andExpect(jsonPath("$.description").value("Release pipeline"));

		mockMvc.perform(delete("/api/jobs/{id}", id))
			.andExpect(status().isNoContent());

		assertThat(jobRepository.findById(id)).isEmpty();
	}

	@Test
	void returnsValidationErrorOnInvalidCreateRequest() throws Exception {
		mockMvc.perform(post("/api/jobs")
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
					{"title":"","description":"Create the CI pipeline"}
					"""))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.status").value(400))
			.andExpect(jsonPath("$.details[0]").exists());
	}

	@Test
	void returns404ForMissingJob() throws Exception {
		mockMvc.perform(get("/api/jobs/{id}", UUID.randomUUID()))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.status").value(404));
	}

	@Test
	void exposesOpenApiDocumentationForJobsEndpoints() throws Exception {
		mockMvc.perform(get("/v3/api-docs"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.paths['/api/jobs']").exists())
			.andExpect(jsonPath("$.paths['/api/jobs/{id}']").exists());
	}
}
