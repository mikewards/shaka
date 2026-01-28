# Build stage
FROM gradle:8.5-jdk17 AS build
WORKDIR /app

# Copy the API project
COPY shaka-api/ .

# Build the application
RUN gradle shadowJar --no-daemon

# Runtime stage
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Install curl for healthchecks
RUN apk add --no-cache curl

# Create non-root user for security
RUN addgroup -g 1001 shaka && \
    adduser -u 1001 -G shaka -D shaka

# Copy the built jar
COPY --from=build /app/build/libs/*-all.jar app.jar

# Set ownership
RUN chown -R shaka:shaka /app

USER shaka

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/v1/health || exit 1

# Environment variables with defaults
ENV PORT=8080 \
    DATABASE_URL="" \
    DATABASE_USER="" \
    DATABASE_PASSWORD="" \
    REDIS_URL=""

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
