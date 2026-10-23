"""서울시 2025-11 원본 XLSX -> EcoCheck JSON. Python 표준 라이브러리만 사용합니다.
좌표를 만들거나 추측하지 않습니다. 주소를 네이버 Geocoding으로 변환하는 단계는 별도입니다.
"""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
SOURCE = "https://data.seoul.go.kr/dataList/OA-15069/F/1/datasetView.do"


def convert(source: Path, destination: Path):
    if destination.exists():
        raise ValueError("출력 파일이 이미 있습니다. 다른 파일명을 지정하세요.")
    with zipfile.ZipFile(source) as book:
        strings = ["".join(si.itertext()) for si in ET.fromstring(book.read("xl/sharedStrings.xml")).findall("s:si", NS)]
        sheet = ET.fromstring(book.read("xl/worksheets/sheet1.xml"))
        rows = []
        for row in sheet.findall(".//s:row", NS):
            cells = {}
            for cell in row.findall("s:c", NS):
                column = "".join(c for c in cell.attrib["r"] if c.isalpha())
                value = cell.find("s:v", NS)
                text = "" if value is None else value.text or ""
                if cell.attrib.get("t") == "s":
                    text = strings[int(text)]
                cells[column] = text.strip()
            rows.append(cells)
    header = next((r for r in rows if r.get("A") == "연번"), None)
    if not header or "설치" not in header.get("C", "") or "종류" not in header.get("F", ""):
        raise ValueError("지원하는 2025-11 서울시 원본 엑셀 형식이 아닙니다. 열 매핑을 확인하세요.")
    items, skipped = [], []
    seen = set()
    for row in rows:
        serial = row.get("A", "")
        if not serial.isdigit():
            continue
        if serial in seen:
            raise ValueError(f"연번 중복: {serial}")
        seen.add(serial)
        if not row.get("B") or not row.get("C"):
            skipped.append({"serial": serial, "reason": "자치구/설치 주소 없음"})
            continue
        raw = row.get("F", "")
        waste_type = "recycling" if "재활용" in raw else "general" if "일반" in raw else "unknown"
        items.append({"id": f"seoul-202511-{serial}", "district": row["B"], "address": row["C"],
                      "detail": row.get("D", ""), "locationType": row.get("E", ""),
                      "wasteType": waste_type, "latitude": None, "longitude": None, "sourceDate": "2025-11"})
    if not items:
        raise ValueError("변환된 데이터가 없습니다.")
    output = {"source": SOURCE, "sourceDate": "2025-11", "originalFile": source.name,
              "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "count": len(items),
              "notice": "원본에는 좌표가 없습니다. 가로휴지통이며 재활용 가능 품목은 현장 확인이 필요합니다.",
              "skipped": skipped, "items": items}
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("x", encoding="utf-8") as stream:
        json.dump(output, stream, ensure_ascii=False, indent=2)
    print(f"변환 {len(items)}개 / 제외 {len(skipped)}개 / 좌표 0개")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    convert(args.source, args.destination)
