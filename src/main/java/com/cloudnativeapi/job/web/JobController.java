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

import java.net.URI;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/jobs")
@Tag(name = "Jobs")
@RequiredArgsConstructor
public class JobController {

	private final JobService jobService;

	@PostMapping
	@Operation(summary = "Create a job")
	public ResponseEntity<JobResponse> create(@Valid @RequestBody JobCreateRequest request) {
		var response = jobService.create(request);
		URI location = ServletUriComponentsBuilder.fromCurrentRequest()
			.path("/{id}")
			.buildAndExpand(response.id())
			.toUri();
		return ResponseEntity.created(location).body(response);
	}

	@GetMapping
	@Operation(summary = "List jobs")
	public List<JobResponse> list() {
		return jobService.findAll();
	}

	@GetMapping("/{id}")
	@Operation(summary = "Get a job by id")
	public JobResponse getById(@PathVariable UUID id) {
		return jobService.findById(id);
	}

	@PutMapping("/{id}")
	@Operation(summary = "Update a job")
	public JobResponse update(@PathVariable UUID id, @Valid @RequestBody JobUpdateRequest request) {
		return jobService.update(id, request);
	}

	@DeleteMapping("/{id}")
	@Operation(summary = "Delete a job")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	public void delete(@PathVariable UUID id) {
		jobService.delete(id);
	}
}
