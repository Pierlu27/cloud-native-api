package com.cloudnativeapi.job.web.dto;

import com.cloudnativeapi.job.domain.JobStatus;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Pattern;

public record JobUpdateRequest(
	@Pattern(regexp = ".*\\S.*", message = "title must not be blank")
	String title,
	@Pattern(regexp = ".*\\S.*", message = "description must not be blank")
	String description,
	JobStatus status
) {
	@AssertTrue(message = "at least one field must be provided")
	public boolean isUpdateRequested() {
		return title != null || description != null || status != null;
	}
}
