package kr.ecocheck;

import java.net.InetSocketAddress;

public final class EcoCheckServerApplication {
    public static void main(String[] args) {
        try {
            ServerDatabaseConfig config = ServerDatabaseConfig.load();
            MySqlScanRecordRepository store = new MySqlScanRecordRepository(config);
            store.initialize();
            EcoCheckHttpServer server =
                    new EcoCheckHttpServer(
                            new InetSocketAddress(config.host(), config.port()), store);
            Runtime.getRuntime().addShutdownHook(new Thread(server::close));
            server.start();
            System.out.printf(
                    "EcoCheck running at http://%s:%d (MySQL connected)%n",
                    config.host(), server.port());
        } catch (Exception e) {
            // JDBC exception text can contain connection details. Keep startup output safe to
            // share.
            System.err.println("Cannot start EcoCheck: " + e.getClass().getSimpleName());
            System.err.println(
                    "Check JDK 17+, backend/.env, MySQL connection and database permissions. See backend/README.md.");
            System.exit(1);
        }
    }
}
