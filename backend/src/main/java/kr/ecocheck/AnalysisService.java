package kr.ecocheck;

import java.io.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.Semaphore;
import javax.imageio.ImageIO;
import kr.ecocheck.Models.*;

/** 사진은 메모리에서만 처리합니다. 결과는 30분 동안만 보관하고 저장은 별도로 요청합니다. */
final class AnalysisService {
  private record Pending(String owner, Analysis value, Instant expires) {}

  private final Map<String, Pending> pending = new HashMap<>();
  private final GeminiClient gemini;
  private final GuideService guides;
  private final Semaphore slots = new Semaphore(2);

  AnalysisService(GeminiClient gemini, GuideService guides) {
    this.gemini = gemini;
    this.guides = guides;
  }

  Analysis analyze(String owner, String mime, String base64) {
    validateImage(mime, base64);
    if (!slots.tryAcquire())
      throw new ApiException(429, "ANALYSIS_BUSY", "다른 사진을 분석 중입니다. 잠시 후 다시 시도해주세요.");
    try {
      synchronized (pending) {
        prune();
        if (pending.size() >= 1000)
          throw new ApiException(503, "ANALYSIS_CAPACITY", "분석 결과 보관 한도에 도달했습니다. 잠시 후 다시 시도해주세요.");
      }
      Prediction p = gemini.classify(mime, base64);
      Guide g = guides.find(p.categoryId()).orElse(null);
      var a =
          new Analysis(
              UUID.randomUUID().toString(),
              p.categoryId(),
              g == null ? "판별 불가" : g.name(),
              g == null ? "미확인" : g.material(),
              g == null ? List.of("물체 하나를 밝은 곳에서 다시 촬영해주세요.") : g.steps(),
              g == null ? "지원 재질인지 확인해주세요." : g.note(),
              p.reason(),
              g != null && !p.needsConfirmation(),
              "gemini",
              gemini.model());
      synchronized (pending) {
        pending.put(a.id(), new Pending(owner, a, Instant.now().plus(Duration.ofMinutes(30))));
      }
      return a;
    } finally {
      slots.release();
    }
  }

  Analysis forSave(String owner, String id) {
    synchronized (pending) {
      prune();
      var item = pending.get(id);
      if (item == null || !item.owner.equals(owner))
        throw new ApiException(404, "ANALYSIS_NOT_FOUND", "분석 결과가 없거나 만료되었습니다. 다시 분석해주세요.");
      if (!item.value.saveAllowed())
        throw new ApiException(422, "ANALYSIS_UNCERTAIN", "확실하지 않은 결과는 AI 기록으로 저장할 수 없습니다.");
      return item.value;
    }
  }

  void remove(String owner, String id) {
    synchronized (pending) {
      var p = pending.get(id);
      if (p != null && p.owner.equals(owner)) pending.remove(id);
    }
  }

  private void prune() {
    pending.values().removeIf(p -> p.expires.isBefore(Instant.now()));
  }

  static void validateImage(String mime, String base64) {
    if (!Set.of("image/jpeg", "image/png").contains(mime))
      throw new ApiException(400, "INVALID_IMAGE_TYPE", "JPEG 또는 PNG 사진만 지원합니다.");
    if (base64.length() > 5_592_408)
      throw new ApiException(413, "IMAGE_TOO_LARGE", "사진은 최대 4MiB입니다.");
    byte[] bytes;
    try {
      bytes = Base64.getDecoder().decode(base64);
    } catch (IllegalArgumentException e) {
      throw new ApiException(400, "INVALID_BASE64", "올바른 base64 사진이 아닙니다.");
    }
    if (bytes.length > 4 * 1024 * 1024)
      throw new ApiException(413, "IMAGE_TOO_LARGE", "사진은 최대 4MiB입니다.");
    try (var stream = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
      var readers = ImageIO.getImageReaders(stream);
      if (!readers.hasNext()) throw new IOException();
      var reader = readers.next();
      try {
        reader.setInput(stream);
        String format = reader.getFormatName();
        if (!(mime.equals("image/jpeg") && format.equalsIgnoreCase("JPEG"))
            && !(mime.equals("image/png") && format.equalsIgnoreCase("PNG")))
          throw new IOException();
        int w = reader.getWidth(0), h = reader.getHeight(0);
        if (w < 1 || h < 1 || (long) w * h > 25_000_000) throw new IOException();
      } finally {
        reader.dispose();
      }
    } catch (IOException | IllegalArgumentException e) {
      throw new ApiException(400, "INVALID_IMAGE", "이미지 형식 또는 크기를 확인해주세요. 최대 2500만 픽셀입니다.");
    }
  }
}
