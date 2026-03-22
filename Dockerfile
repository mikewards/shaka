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

# System deps + Python with scientific packages (single layer, build deps cleaned)
RUN apk add --no-cache curl python3 py3-pip hdf5 netcdf eccodes && \
    apk add --no-cache --virtual .build-deps \
        gcc g++ musl-dev python3-dev hdf5-dev netcdf-dev && \
    pip3 install --no-cache-dir --break-system-packages \
        copernicusmarine xarray netCDF4 numpy Pillow h5py boto3 \
        ecmwf-opendata cfgrib && \
    apk del .build-deps && \
    rm -rf /root/.cache /tmp/*

# Copy the built jar
COPY --from=build /app/build/libs/*-all.jar app.jar

# Copy weather pipeline script
COPY scripts/weather_pipeline.py /app/scripts/weather_pipeline.py

# Copy PMTiles land/lakes mask files
COPY data/ne_50m_land.pmtiles /app/data/ne_50m_land.pmtiles
COPY data/ne_50m_lakes.pmtiles /app/data/ne_50m_lakes.pmtiles

# Create weather data directory
RUN mkdir -p /data/weather

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/v1/health || exit 1

# Non-sensitive env defaults only (secrets injected by Railway at runtime)
ENV PORT=8080 \
    WEATHER_DATA_DIR="/data/weather" \
    WEATHER_PIPELINE_SCRIPT="/app/scripts/weather_pipeline.py"

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
