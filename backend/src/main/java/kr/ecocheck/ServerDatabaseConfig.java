package kr.ecocheck;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

record ServerDatabaseConfig(String host, int port, String dbUrl, String dbUser, String dbPassword) {
    static ServerDatabaseConfig load() throws IOException {
        Map<String, String> values = new HashMap<>();
        Path file = Path.of(".env");

        if (Files.exists(file)) {
            for (String line : Files.readAllLines(file)) {
                line = line.strip();

                if (line.isEmpty() || line.startsWith("#"))
                    continue;
                int equals = line.indexOf('=');

                if (equals < 1)
                    throw new IllegalArgumentException("Invalid .env line");
                String value = line.substring(equals + 1).strip();

                if (value.length() >= 2
                        && ((value.startsWith("\"") && value.endsWith("\""))
                                || (value.startsWith("'") && value.endsWith("'")))) {
                    value = value.substring(1, value.length() - 1);
                }
                values.put(line.substring(0, equals).strip(), value);
            }
        }
        values.putAll(System.getenv());
        int port = Integer.parseInt(values.getOrDefault("ECOCHECK_PORT", "8080"));

        if (port < 1 || port > 65535)
            throw new IllegalArgumentException("Invalid ECOCHECK_PORT");

        return new ServerDatabaseConfig(
                values.getOrDefault("ECOCHECK_HOST", "127.0.0.1"),
                port,
                required(values, "ECOCHECK_DB_URL"),
                required(values, "ECOCHECK_DB_USER"),
                required(values, "ECOCHECK_DB_PASSWORD"));
    }

    private static String required(Map<String, String> values, String name) {
        String value = values.get(name);

        if (value == null || value.isBlank())
            throw new IllegalArgumentException("Set " + name + " in backend/.env or environment");

        return value;
    }
}
