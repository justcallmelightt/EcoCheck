package kr.ecocheck;

import java.net.InetSocketAddress;

/** IntelliJ에서 이 클래스의 main을 실행하세요. DB가 없어도 서버는 켜지고 /health가 503을 반환합니다. */
public final class EcoCheckServerApplication {
  public static void main(String[] args) throws Exception {
    var config = AppConfig.load();
    var guides = new GuideService();
    var db = new MySqlRepository(config);
    if (args.length > 0) {
      AdminCommands.run(args, config, db);
      return;
    }
    var gemini = new GeminiClient(config, guides);
    var server =
        new EcoCheckHttpServer(
            new InetSocketAddress(config.host(), config.port()),
            config,
            db,
            guides,
            new AnalysisService(gemini, guides));
    Runtime.getRuntime().addShutdownHook(new Thread(server::close));
    server.start();
    System.out.println("EcoCheck: http://" + config.host() + ":" + server.port());
    System.out.println(
        "MySQL="
            + (db.healthy() ? "ready" : "설정/schema.sql 확인 필요")
            + ", Gemini="
            + (gemini.configured() ? "키 설정됨 (실제 호출 미확인)" : "키 미설정"));
  }
}
