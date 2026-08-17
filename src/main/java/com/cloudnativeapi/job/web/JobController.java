package com.cloudnativeapi.job.web;

import com.cloudnativeapi.job.service.JobService;
import com.cloudnativeapi.job.web.dto.JobCreateRequest;
import com.cloudnativeapi.job.web.dto.JobResponse;
import com.cloudnativeapi.job.web.dto.JobUpdateRequest;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/jobs")
@Tag(name = "Jobs")
@RequiredArgsConstructor
public class JobController {

	private static final Logger log = LoggerFactory.getLogger(JobController.class);

	private final JobService jobService;

	@PostMapping
	@Operation(summary = "Create a job", description = "Creates a job with PENDING status and server-generated timestamps.")
	public ResponseEntity<JobResponse> create(@Valid @RequestBody JobCreateRequest request) {
		log.info("Received POST /api/jobs request");
		var response = jobService.create(request);
		URI location = ServletUriComponentsBuilder.fromCurrentRequest()
			.path("/{id}")
			.buildAndExpand(response.id())
			.toUri();
		log.info("Created job id={} successfully", response.id());
		return ResponseEntity.created(location).body(response);
	}

	@GetMapping
	@Operation(summary = "List jobs", description = "Returns every stored job.")
	public List<JobResponse> list() {
		log.info("Received GET /api/jobs request");
		var jobs = jobService.findAll();
		log.info("Listed {} jobs successfully", jobs.size());
		return jobs;
	}

	@GetMapping("/{id}")
	@Operation(summary = "Get a job by id", description = "Returns a single job or a consistent 404 error response.")
	public JobResponse getById(@PathVariable UUID id) {
		log.info("Received GET /api/jobs/{} request", id);
		var response = jobService.findById(id);
		log.info("Retrieved job id={} successfully", id);
		return response;
	}

	@PutMapping("/{id}")
	@Operation(summary = "Update a job", description = "Updates one or more job fields and refreshes updatedAt.")
	public JobResponse update(@PathVariable UUID id, @Valid @RequestBody JobUpdateRequest request) {
		log.info("Received PUT /api/jobs/{} request", id);
		var response = jobService.update(id, request);
		log.info("Updated job id={} successfully", id);
		return response;
	}

	@DeleteMapping("/{id}")
	@Operation(summary = "Delete a job", description = "Deletes a job and returns 404 when it does not exist.")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	public void delete(@PathVariable UUID id) {
		log.info("Received DELETE /api/jobs/{} request", id);
		jobService.delete(id);
		log.info("Deleted job id={} successfully", id);
	}
}
