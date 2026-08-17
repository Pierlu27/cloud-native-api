# ================================================================
# Build stage: compile and package the Spring Boot application.
# ================================================================
# Use a full JDK image to compile the Spring Boot application.
FROM eclipse-temurin:25-jdk AS build

# Set the working directory for the build stage.
WORKDIR /workspace

# Copy build configuration first to make dependency-related layers cacheable.
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
# Ensure the Gradle wrapper can be executed inside the container.
RUN chmod +x gradlew

# Copy the application source and create the executable Spring Boot JAR.
COPY src ./src
RUN ./gradlew --no-daemon bootJar && cp $(find build/libs -name '*.jar' ! -name '*-plain.jar') app.jar

# ================================================================
# Runtime stage: run only the packaged application.
# ================================================================
# Use a lightweight JRE-only image to run the application.
FROM eclipse-temurin:25-jre-alpine

# Install the health-check utility and create an unprivileged runtime user.
RUN apk add --no-cache curl \
    && addgroup --system appuser \
    && adduser --system --uid 10001 --ingroup appuser appuser

# Store the packaged application in its own runtime directory.
WORKDIR /app
# Copy only the built artifact from the previous stage.
COPY --from=build /workspace/app.jar app.jar

# Run the container as a non-root user for improved security.
USER appuser

# Document the HTTP port exposed by the application.
EXPOSE 8080

# Start the Spring Boot application when the container launches.
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
