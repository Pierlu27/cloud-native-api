package com.cloudnativeapi.job.service;

import com.cloudnativeapi.job.domain.Job;
import com.cloudnativeapi.job.domain.JobStatus;
import com.cloudnativeapi.job.repository.JobRepository;
import com.cloudnativeapi.job.web.dto.JobCreateRequest;
import com.cloudnativeapi.job.web.dto.JobResponse;
import com.cloudnativeapi.job.web.dto.JobUpdateRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import lombok.RequiredArgsConstructor;

import java.util.List;
import java.util.UUID;

@Service
@Transactional
@RequiredArgsConstructor
public class JobService {

	private final JobRepository jobRepository;

	public JobResponse create(JobCreateRequest request) {
		var job = new Job();
		job.setTitle(request.title());
		job.setDescription(request.description());
		job.setStatus(JobStatus.PENDING);
		return toResponse(jobRepository.save(job));
	}

	@Transactional(readOnly = true)
	public List<JobResponse> findAll() {
		return jobRepository.findAll().stream().map(JobService::toResponse).toList();
	}

	@Transactional(readOnly = true)
	public JobResponse findById(UUID id) {
		return toResponse(findJob(id));
	}

	public JobResponse update(UUID id, JobUpdateRequest request) {
		var job = findJob(id);
		if (request.title() != null) {
			job.setTitle(request.title());
		}
		if (request.description() != null) {
			job.setDescription(request.description());
		}
		if (request.status() != null) {
			job.setStatus(request.status());
		}
		return toResponse(jobRepository.save(job));
	}

	public void delete(UUID id) {
		var job = findJob(id);
		jobRepository.delete(job);
	}

	private Job findJob(UUID id) {
		return jobRepository.findById(id).orElseThrow(() -> new JobNotFoundException(id));
	}

	private static JobResponse toResponse(Job job) {
		return new JobResponse(
			job.getId(),
			job.getTitle(),
			job.getDescription(),
			job.getStatus() == null ? JobStatus.PENDING : job.getStatus(),
			job.getCreatedAt(),
			job.getUpdatedAt()
		);
	}
}
