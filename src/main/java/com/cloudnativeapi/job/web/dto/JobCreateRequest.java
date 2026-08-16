package com.cloudnativeapi.job.web.dto;

import jakarta.validation.constraints.NotBlank;

public record JobCreateRequest(
	@NotBlank(message = "title is required")
	String title,
	@NotBlank(message = "description is required")
	String description
) {
}
