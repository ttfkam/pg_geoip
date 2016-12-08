-- ===========================================================================
-- newsfeeds PostgreSQL extension
-- Miles Elam <miles@geekspeak.org>
--
-- Depends on file_fdw
--            GeoIP files (https://dev.maxmind.com/geoip/)
-- ---------------------------------------------------------------------------

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION geoip" to load this file. \quit

CREATE SERVER geoip_files
  FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE "GeoLite2CityBlocksIPv4" (
    network cidr NOT NULL,
    geoname_id integer,
    registered_country_geoname_id integer,
    represented_country_geoname_id integer,
    is_anonymous_proxy boolean NOT NULL,
    is_satellite_provider boolean NOT NULL,
    postal_code character varying(16),
    latitude real,
    longitude real,
    accuracy_radius integer)
  SERVER geoip_files
  OPTIONS (
    delimiter ',',
    filename '/var/www/geoip/GeoLite2-City-Blocks-IPv4.csv',
    format 'csv',
    header 'TRUE');

CREATE FOREIGN TABLE "GeoLite2CityBlocksIPv6" (
    network cidr NOT NULL,
    geoname_id integer,
    registered_country_geoname_id integer,
    represented_country_geoname_id integer,
    is_anonymous_proxy boolean NOT NULL,
    is_satellite_provider boolean NOT NULL,
    postal_code character varying(16),
    latitude real,
    longitude real,
    accuracy_radius integer)
  SERVER geoip_files
  OPTIONS (
    delimiter ',',
    filename '/var/www/geoip/GeoLite2-City-Blocks-IPv6.csv',
    format 'csv',
    header 'TRUE');

CREATE FOREIGN TABLE "GeoLite2CityLocations_en" (
    geoname_id integer NOT NULL,
    locale_code character varying,
    continent_code character(2),
    continent_name character varying,
    country_iso_code character varying,
    country_name character varying,
    subdivision_1_iso_code character varying(3),
    subdivision_1_name character varying,
    subdivision_2_iso_code character varying(3),
    subdivision_2_name character varying,
    city_name character varying,
    metro_code integer,
    time_zone character varying)
  SERVER geoip_files
  OPTIONS (
    delimiter ',',
    filename '/var/www/geoip/GeoLite2-City-Locations-en.csv',
    format 'csv',
    header 'TRUE');

CREATE MATERIALIZED VIEW continents AS
  SELECT DISTINCT continent_code AS id, continent_name AS name
    FROM "GeoLite2CityLocations_en"
  WITH NO DATA;

CREATE MATERIALIZED VIEW countries AS
  SELECT DISTINCT country_iso_code AS id, country_name AS name
    FROM "GeoLite2CityLocations_en"
    WHERE (country_name IS NOT NULL)
  WITH NO DATA;

CREATE MATERIALIZED VIEW locations AS
  SELECT geoname_id AS id, locale_code AS locale, continent_code AS continent,
        country_iso_code AS country, subdivision_1_iso_code AS sub1,
        subdivision_2_name AS sub2_name, city_name AS city, metro_code AS metro,
        ((('x'::text || substr(md5((time_zone)::text), 1, 8)))::bit(32))::integer AS timezone
    FROM "GeoLite2CityLocations_en"
  WITH NO DATA;

CREATE MATERIALIZED VIEW networks AS
  SELECT network, false AS ipv6, geoname_id AS location,
        registered_country_geoname_id AS registered_country,
        represented_country_geoname_id AS represented_country, is_anonymous_proxy,
        is_satellite_provider, postal_code, latitude, longitude, accuracy_radius
    FROM "GeoLite2CityBlocksIPv4"
  UNION ALL
  SELECT network, true AS ipv6, geoname_id AS location,
         registered_country_geoname_id AS registered_country,
         represented_country_geoname_id AS represented_country, is_anonymous_proxy,
         is_satellite_provider, postal_code, latitude, longitude, accuracy_radius
    FROM "GeoLite2CityBlocksIPv6"
  WITH NO DATA;

CREATE MATERIALIZED VIEW subdivisions AS
  SELECT DISTINCT country_iso_code AS country, subdivision_1_iso_code AS code,
         subdivision_1_name AS name
    FROM "GeoLite2CityLocations_en"
    WHERE (subdivision_1_iso_code IS NOT NULL)
  WITH NO DATA;

COMMENT ON MATERIALIZED VIEW subdivisions AS
'Subdivisions refers to states, provinces, etc., but are country-specific, not globally uniform';

CREATE MATERIALIZED VIEW timezones AS
  SELECT DISTINCT time_zone,
         ((('x'::text || substr(md5((time_zone)::text), 1, 8)))::bit(32))::integer AS tzhash
    FROM "GeoLite2CityLocations_en"
    WHERE (time_zone IS NOT NULL)
  WITH NO DATA;

CREATE UNIQUE INDEX locations_udx ON locations USING btree (id);

CREATE INDEX networks_idx ON networks USING gist (network inet_ops);
