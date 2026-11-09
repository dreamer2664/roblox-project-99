"""Generate the render shot list from the built place's manifest (bbox-accurate)."""
import json, os
ROOT = "/home/user/rblx99"
m = json.load(open(os.path.join(ROOT, "out", "manifest.json")))
md = m["models"]

def bb(name):
    b = md[name]
    return b["min"], b["max"]

def add(a, b, k=0.5):
    return [a[i] + (b[i] - a[i]) * k for i in range(3)]

gc_min, gc_max = bb("Stations/GrandCentral")
tr_min, tr_max = bb("RollingStock/Train_1A_Meridian")
vi_min, vi_max = bb("Infrastructure/Viaduct")
tu_min, tu_max = bb("Infrastructure/Tunnel")
hi_min, hi_max = bb("Scenery/Hillside")
hb_min, hb_max = bb("Stations/HarbourTerminus")
tr2_min, tr2_max = bb("RollingStock/Train_2B_Harbour")

# warm fill lights inside the trainshed
shed_lights = []
for i in range(6):
    x = 30 + i * 24
    shed_lights.append({"pos": [x, 16, -6], "energy": 9000, "size": 26, "size_y": 8,
                        "color": [1.0, 0.86, 0.66], "target": [x, 0, 0]})

shots = [
 # 1 hero: consist at the platform inside the trainshed
 {"name": "01_hero_consist_at_platform",
  "pos": [tr_min[0] - 26, 7.5, 24], "target": [tr_max[0] - 6, 4.0, 2],
  "focal": 42, "world": "golden", "samples": 40, "w": 1600, "h": 900,
  "lights": shed_lights, "exposure": 0.25},
 # 2 cab-front three-quarter of the locomotive
 {"name": "02_locomotive_three_quarter",
  "pos": [tr_max[0] + 12, 3.2, 13], "target": [tr_min[0] + 6, 3.0, 1],
  "focal": 50, "world": "golden", "samples": 40, "w": 1600, "h": 900,
  "lights": shed_lights, "exposure": 0.3},
 # 3 terminus facade from the street - "realistic building" shot
 {"name": "03_terminus_facade",
  "pos": [gc_max[0] * 0.45, 16, gc_max[2] + 72], "target": [gc_max[0] * 0.42, 22, 4],
  "focal": 32, "world": "sunset", "samples": 40, "w": 1600, "h": 900, "exposure": 0.15},
 # 4 aerial of the whole station throat
 {"name": "04_station_aerial",
  "pos": [gc_max[0] * 0.2, 86, 96], "target": [72, 6, -6],
  "focal": 30, "world": "sunset", "samples": 40, "w": 1600, "h": 900, "exposure": 0.2},
 # 5 the platform under the canopy, looking down the train
 {"name": "05_platform_canopy",
  "pos": [tr_max[0] + 24, 3.4, -9.5], "target": [tr_min[0] - 10, 3.0, -8.0],
  "focal": 40, "world": "golden", "samples": 40, "w": 1600, "h": 900,
  "lights": shed_lights, "exposure": 0.3},
 # 6 viaduct over the river
 {"name": "06_viaduct_river",
  "pos": [add(vi_min, vi_max, 0.5)[0] - 40, 26, add(vi_min, vi_max, 0.5)[2] + 95],
  "target": [add(vi_min, vi_max, 0.5)[0] + 6, 2, add(vi_min, vi_max, 0.5)[2] + 4],
  "focal": 34, "world": "sunset", "samples": 40, "w": 1600, "h": 900, "exposure": 0.1},
 # 7 tunnel portal in the hillside
 {"name": "07_tunnel_portal",
  "pos": [tu_min[0] - 54, 6.5, tu_min[2] + 26], "target": [tu_min[0] + 4, 5, tu_min[2] + 4],
  "focal": 40, "world": "overcast", "samples": 40, "w": 1600, "h": 900, "exposure": 0.15},
 # 8 train on the second line, mountainside
 {"name": "08_train_on_the_line",
  "pos": [tr2_min[0] - 30, 9, tr2_min[2] - 26], "target": [tr2_max[0] - 6, 3.2, tr2_max[2]],
  "focal": 44, "world": "day", "samples": 40, "w": 1600, "h": 900, "exposure": 0.2},
 # 9 harbour terminus
 {"name": "09_harbour_terminus",
  "pos": [hb_max[0] - 20, 18, hb_min[2] - 66], "target": [hb_min[0] + 40, 18, hb_min[2] + 20],
  "focal": 34, "world": "sunset", "samples": 40, "w": 1600, "h": 900, "exposure": 0.15},
 # 10 the city
 {"name": "10_city_district",
  "pos": [120, 74, 74], "target": [200, 10, -200],
  "focal": 40, "world": "day", "samples": 40, "w": 1600, "h": 900, "exposure": 0.2},
]
json.dump({"outdir": os.path.join(ROOT, "renders"), "shots": shots},
          open(os.path.join(ROOT, "shots.json"), "w"), indent=1)
print("shots:", len(shots))
