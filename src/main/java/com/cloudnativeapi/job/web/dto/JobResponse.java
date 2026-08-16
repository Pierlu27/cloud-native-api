package com.cloudnativeapi.job.web.dto;

import com.cloudnativeapi.job.domain.JobStatus;

import java.time.Instant;
import java.util.UUID;

public record JobResponse(
	UUID id,
	String title,
	String description,
	JobStatus status,
	Instant createdAt,
	Instant updatedAt
) {
}
