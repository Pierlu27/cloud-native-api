package com.cloudnativeapi.job.service;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.UUID;

@Getter
@RequiredArgsConstructor
public class JobNotFoundException extends RuntimeException {

	private final UUID id;
}
