# pico_so_bench

Набор бенчмарков для сравнения производительности разных сборок [Tarantool](https://git.picodata.io/core/tarantool).

Основная цель — численно оценить, не вносит ли новая ветка регрессии по TPS относительно базовой, и проверить, как поведение меняется при росте объёма данных (параметр `SCALE`).

## Что тестируется

| Бенчмарк | Операции | Сравнение веток |
|---|---|---|
| `bench_memtx.lua` | INSERT, GET, SELECT (range), UPDATE, REPLACE, DELETE | Да |
| `bench_vinyl.lua` | те же операции, движок vinyl | Да |
| `bench_sort_order.lua` | INSERT, SELECT\_RANGE, SELECT\_RANGE\_REV, UPDATE, REPLACE, DELETE × три режима сортировки (plain / all\_desc / mixed) | Только если в обеих ветках есть поддержка sort\_order |

Подробнее о каждом бенчмарке — в [reports/REPORTS.md](reports/REPORTS.md).

## Быстрый старт

```bash
# Собрать результаты и построить графики
make all
```

Результаты сохраняются в `results/`, графики — в `plots_stat/`.

## Запуск вручную

```bash
# Одна ветка, несколько масштабов, 10 итераций
./run_repeated_scaling.sh ~/.local/bin/tarantool-master master 10 1 10 50
./run_repeated_scaling.sh ~/.local/bin/tarantool-so    so    10 1 10 50

# Построить графики (base=master, target=so)
uv run ./scripts/plot_statistical.py --base master --target so
uv run ./scripts/compare_builds.py   --base master --target so

# Если у target нет sort_order — исключить этот бенчмарк из сравнения
uv run ./scripts/plot_statistical.py --base master --target myco --no-sort-order
uv run ./scripts/compare_builds.py   --base master --target myco --no-sort-order
```

## Параметры скриптов

### `run_repeated_scaling.sh`

```
./run_repeated_scaling.sh <binary> <prefix> <iterations> <scale1> [scale2] ...
```

| Параметр | Описание |
|---|---|
| `binary` | Путь к бинарнику tarantool |
| `prefix` | Имя ветки/сборки (используется как ключ в CSV) |
| `iterations` | Число повторов на каждый scale (для доверительных интервалов) |
| `scale` | Коэффициент объёма данных (1 → базовый, 10 → ×10 строк) |

| Scale | Memtx строк | Vinyl строк | Sort Order строк |
|---|---|---|---|
| 1 | 100 000 | 50 000 | 60 000 |
| 10 | 1 000 000 | 500 000 | 600 000 |
| 50 | 5 000 000 | 2 500 000 | 3 000 000 |

### `plot_statistical.py` / `compare_builds.py`

| Флаг | По умолчанию | Описание |
|---|---|---|
| `--base` | `master` | Имя базовой ветки (prefix в CSV) |
| `--target` | `so` | Имя целевой ветки |
| `--results` | `results` | Директория с результатами |
| `--output` | `plots_stat` | Директория для графиков (plot_statistical) |
| `--no-sort-order` | выключен | Исключить bench\_sort\_order из сравнения |

## Структура результатов

```
results/
  <prefix>_s<scale>_i<iter>/
    summary.csv          # TPS по каждой операции
    meta.txt             # бинарник, версия, дата
    bench_memtx/
    bench_vinyl/
    bench_sort_order/
```

## Зависимости

- Tarantool 2.11+
- Python 3.10+ (`pandas`, `matplotlib`, `seaborn`, `scipy`)
- `uv` для управления окружением

```bash
uv sync
```
