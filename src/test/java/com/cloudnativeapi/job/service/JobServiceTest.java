package com.cloudnativeapi.job.service;

import com.cloudnativeapi.job.domain.Job;
import com.cloudnativeapi.job.domain.JobStatus;
import com.cloudnativeapi.job.repository.JobRepository;
import com.cloudnativeapi.job.web.dto.JobCreateRequest;
import com.cloudnativeapi.job.web.dto.JobUpdateRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class JobServiceTest {

	@Mock
	private JobRepository jobRepository;

	@InjectMocks
	private JobService jobService;

	@Test
	void createJobSetsPendingStatus() {
		when(jobRepository.save(any(Job.class))).thenAnswer(invocation -> {
			var job = invocation.getArgument(0, Job.class);
			job.setId(UUID.fromString("11111111-1111-1111-1111-111111111111"));
			return job;
		});

		var response = jobService.create(new JobCreateRequest("Build pipeline", "Create the CI pipeline"));

		assertThat(response.id()).isEqualTo(UUID.fromString("11111111-1111-1111-1111-111111111111"));
		assertThat(response.status()).isEqualTo(JobStatus.PENDING);
		assertThat(response.title()).isEqualTo("Build pipeline");
		assertThat(response.description()).isEqualTo("Create the CI pipeline");
		verify(jobRepository).save(any(Job.class));
	}

	@Test
	void findAllMapsEntitiesToResponses() {
		var job = new Job();
		job.setTitle("Build pipeline");
		job.setDescription("Create the CI pipeline");
		job.setStatus(JobStatus.PENDING);
		job.setId(UUID.fromString("22222222-2222-2222-2222-222222222222"));
		setTimestamps(job);
		when(jobRepository.findAll()).thenReturn(List.of(job));

		var responses = jobService.findAll();

		assertThat(responses).hasSize(1);
		assertThat(responses.getFirst().id()).isEqualTo(job.getId());
	}

	@Test
	void updateJobChangesMutableFields() {
		var job = new Job();
		job.setTitle("Build pipeline");
		job.setDescription("Create the CI pipeline");
		job.setStatus(JobStatus.PENDING);
		job.setId(UUID.fromString("33333333-3333-3333-3333-333333333333"));
		setTimestamps(job);
		when(jobRepository.findById(job.getId())).thenReturn(Optional.of(job));
		when(jobRepository.save(any(Job.class))).thenAnswer(invocation -> invocation.getArgument(0));

		var response = jobService.update(job.getId(), new JobUpdateRequest("Release pipeline", null, JobStatus.RUNNING));

		assertThat(response.title()).isEqualTo("Release pipeline");
		assertThat(response.status()).isEqualTo(JobStatus.RUNNING);
		verify(jobRepository).save(job);
	}

	@Test
	void deleteMissingJobThrowsNotFound() {
		var id = UUID.fromString("44444444-4444-4444-4444-444444444444");
		when(jobRepository.findById(id)).thenReturn(Optional.empty());

		assertThatThrownBy(() -> jobService.delete(id))
			.isInstanceOf(JobNotFoundException.class)
			.satisfies(exception -> assertThat(((JobNotFoundException) exception).getId()).isEqualTo(id));
	}

	private static void setTimestamps(Job job) {
		var now = Instant.parse("2026-08-16T11:00:00Z");
		job.setId(job.getId());
		try {
			var createdAtField = Job.class.getDeclaredField("createdAt");
			createdAtField.setAccessible(true);
			createdAtField.set(job, now);
			var updatedAtField = Job.class.getDeclaredField("updatedAt");
			updatedAtField.setAccessible(true);
			updatedAtField.set(job, now);
		} catch (ReflectiveOperationException exception) {
			throw new IllegalStateException(exception);
		}
	}
}
