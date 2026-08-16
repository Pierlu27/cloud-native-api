package com.cloudnativeapi.job.repository;

import com.cloudnativeapi.job.domain.Job;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface JobRepository extends JpaRepository<Job, UUID> {
}
