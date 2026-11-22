#!/usr/bin/env python3
"""Match Seoul bin road addresses to the supplied address reference DB.

The exported X/Y is a building entrance proxy, not a surveyed bin position.
No source row or nationwide address collection is exported.
"""

import argparse
import collections
import json
import re
from pathlib import Path


ROAD_ADDRESS = re.compile(r"^(.+(?:로|길))\s+(\d+)(?:-(\d+))?$")


def key(district, address):
    match = ROAD_ADDRESS.fullmatch(address.strip())
    if not match:
        return None
    road, main, sub = match.groups()
    return district.strip(), road.strip(), int(main), int(sub or 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bins", type=Path)
    parser.add_argument("seoul_reference", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    bins = json.loads(args.bins.read_text(encoding="utf-8"))["items"]
    groups = collections.defaultdict(list)
    for item in bins:
        address_key = key(item["district"], item["address"])
        if address_key:
            groups[address_key].append(item["id"])

    candidates = collections.defaultdict(set)
    with args.seoul_reference.open(encoding="cp949") as source:
        for line in source:
            fields = line.rstrip("\r\n").split("|")
            if len(fields) != 18 or fields[3] != "서울특별시":
                continue
            try:
                address_key = (
                    fields[4].strip(), fields[7].strip(), int(fields[9]), int(fields[10])
                )
                x, y = float(fields[16]), float(fields[17])
            except ValueError:
                continue
            if address_key in groups:
                candidates[address_key].add((x, y))

    matches = []
    ambiguous = 0
    for address_key, bin_ids in sorted(groups.items()):
        points = candidates.get(address_key, set())
        if len(points) != 1:
            ambiguous += len(points) > 1
            continue
        x, y = next(iter(points))
        district, road, main_number, sub_number = address_key
        matches.append({
            "district": district,
            "roadAddress": f"{road} {main_number}" + (f"-{sub_number}" if sub_number else ""),
            "binIds": bin_ids,
            "x": x,
            "y": y,
        })

    result = {
        "source": "행정안전부 도로명주소 위치정보요약DB 2026-09; 공공누리 제1유형",
        "sourceUrl": "https://www.data.go.kr/data/15050410/fileData.do",
        "binSource": "서울시 가로휴지통 2025-11",
        "coordinateKind": "원본 X/Y 건물 출입구 좌표; 좌표계 확인 및 경위도 변환 전",
        "accuracyNote": "주소가 일치한 건물 출입구의 대리 좌표이며 수거함의 실제 위치가 아닙니다.",
        "matchedAddresses": len(matches),
        "matchedBins": sum(len(item["binIds"]) for item in matches),
        "ambiguousAddressesExcluded": ambiguous,
        "items": matches,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"주소 {len(matches):,}건, 수거함 {result['matchedBins']:,}건 매칭; 중복 좌표 주소 {ambiguous:,}건 제외")


if __name__ == "__main__":
    main()
