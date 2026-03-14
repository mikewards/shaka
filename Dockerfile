# Build stage
FROM gradle:8.5-jdk17 AS build
WORKDIR /app

# Copy the API project
COPY shaka-api/ .

# Build the application
RUN gradle shadowJar --no-daemon

# Runtime stage — Debian-based for Python/NumPy support
FROM eclipse-temurin:17-jre
WORKDIR /app

# Install system deps: curl (healthcheck), Python 3 + pip (weather pipeline)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

# Install Python packages for weather pipeline
RUN pip3 install --no-cache-dir --break-system-packages \
    copernicusmarine xarray netCDF4 numpy Pillow

# Create non-root user for security
RUN groupadd -g 1001 shaka && \
    useradd -u 1001 -g shaka -m shaka

# Copy the built jar
COPY --from=build /app/build/libs/*-all.jar app.jar

# Copy weather pipeline script
COPY scripts/weather_pipeline.py /app/scripts/weather_pipeline.py

# Create weather data directory
RUN mkdir -p /data/weather && chown -R shaka:shaka /app /data/weather

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
    REDIS_URL="" \
    WEATHER_DATA_DIR="/data/weather" \
    WEATHER_PIPELINE_SCRIPT="/app/scripts/weather_pipeline.py"

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
