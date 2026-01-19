# ttf_advance_width_adjuster

ttf 폰트 파일의 자간 간격을 조절해 줌

사용법:
```bash
  ruby ttf_adjuster.rb input.ttf output.ttf scale_factor
```
예시:
```bash
  ruby ttf_adjuster.rb font.ttf font_narrow.ttf 0.9
```

scale_factor 예시:
  * 0.9  - 10% 줄임 (90% 크기)
  * 0.8  - 20% 줄임 (80% 크기)
  * 0.85 - 15% 줄임 (85% 크기)
