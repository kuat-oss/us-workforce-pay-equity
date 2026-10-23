# raw csv -> duckdb -> dq checks -> tables, charts, dashboard data
# usage: python src/run_pipeline.py
from pathlib import Path
import json
import os

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
TABLES = ROOT / "outputs" / "tables"
CHARTS = ROOT / "outputs" / "charts"
DASH_DATA = ROOT / "dashboard" / "data.js"

ANALYSIS_VIEWS = [
    "dq_report",
    "dq_employment_reconciliation",
    "a_pay_ratio_by_year",
    "a_pay_ratio_by_category",
    "a_occupation_gap_ranking",
    "a_female_share_bands",
    "a_occupation_scatter",
    "a_earnings_by_sex_quarterly",
    "a_earnings_yoy",
    "a_earnings_by_race",
    "a_gender_ratio_by_age",
    "a_industry_shock",
    "a_employment_trend",
]

BLUE, ORANGE, GREY, RED = "#2a6fdb", "#e8833a", "#8a8f98", "#c8423b"
plt.rcParams.update({
    "figure.dpi": 140, "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.alpha": 0.25, "font.size": 10,
})


def build_database() -> duckdb.DuckDBPyConnection:
    (ROOT / "outputs").mkdir(exist_ok=True)
    DASH_DATA.parent.mkdir(exist_ok=True)
    # SQL uses repo-relative paths, so execute from the repo root
    os.chdir(ROOT)
    con = duckdb.connect(str(ROOT / "outputs" / "workforce.duckdb"))
    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        con.execute(sql_file.read_text())
        print(f"  ran {sql_file.name}")
    return con


def export_tables(con) -> dict:
    TABLES.mkdir(parents=True, exist_ok=True)
    frames = {}
    for view in ANALYSIS_VIEWS:
        df = con.execute(f"SELECT * FROM {view}").df()
        df.to_csv(TABLES / f"{view}.csv", index=False)
        frames[view] = df
    print(f"  exported {len(frames)} tables to outputs/tables/")
    return frames


def chart_pay_ratio_trend(f):
    df = f["a_earnings_by_sex_quarterly"]
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.plot(df["quarter_start"], df["men"], color=BLUE, lw=2, label="Men")
    ax.plot(df["quarter_start"], df["women"], color=ORANGE, lw=2, label="Women")
    fig.suptitle("Median weekly earnings, full-time workers (BLS CPS, 2010-2020)", x=0.02, ha="left", fontsize=11)
    ax.yaxis.set_major_formatter(mtick.StrMethodFormatter("${x:,.0f}"))
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(CHARTS / "01_weekly_earnings_by_sex.png")
    plt.close(fig)


def chart_category_gap(f):
    df = f["a_pay_ratio_by_category"].sort_values("pay_ratio_2016")
    fig, ax = plt.subplots(figsize=(8, 4.2))
    y = range(len(df))
    ax.barh(y, df["pay_ratio_2016"], color=BLUE)
    ax.set_yticks(list(y), df["major_category"])
    ax.axvline(100, color=GREY, ls="--", lw=1)
    for i, v in enumerate(df["pay_ratio_2016"]):
        ax.text(v + 0.5, i, f"{v:.1f}", va="center", fontsize=9)
    ax.set_xlim(60, 105)
    ax.set_xlabel("Women's pay as % of men's in the same occupation")
    fig.suptitle("Gender pay ratio by job family, 2016 (100 = parity)", x=0.02, ha="left", fontsize=11)
    fig.tight_layout()
    fig.savefig(CHARTS / "02_pay_ratio_by_category.png")
    plt.close(fig)


def chart_scatter(f):
    df = f["a_occupation_scatter"]
    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.scatter(df["percent_female"], df["median_earnings_all"],
               s=df["total_workers"] / 20000, alpha=0.45, color=BLUE, edgecolor="white", lw=0.4)
    ax.set_xlabel("% of workers who are women")
    ax.set_ylabel("Median annual earnings")
    ax.yaxis.set_major_formatter(mtick.StrMethodFormatter("${x:,.0f}"))
    fig.suptitle("Female share vs median pay by occupation, 2016 (bubble = headcount)", x=0.02, ha="left", fontsize=11)
    fig.tight_layout()
    fig.savefig(CHARTS / "03_female_share_vs_earnings.png")
    plt.close(fig)


def chart_industry_shock(f):
    df = f["a_industry_shock"].sort_values("pct_change_2020")
    fig, ax = plt.subplots(figsize=(8, 4.8))
    y = range(len(df))
    colors = [RED if v < -5 else GREY for v in df["pct_change_2020"]]
    ax.barh(y, df["pct_change_2020"], color=colors)
    ax.set_yticks(list(y), df["industry"])
    ax.axvline(0, color="black", lw=0.8)
    for i, v in enumerate(df["pct_change_2020"]):
        ax.text(v - 0.3 if v < 0 else v + 0.3, i, f"{v:+.1f}%", va="center",
                ha="right" if v < 0 else "left", fontsize=9)
    ax.set_xlim(df["pct_change_2020"].min() - 5, max(3, df["pct_change_2020"].max() + 3))
    fig.suptitle("Employment change by sector, 2019 to 2020", x=0.02, ha="left", fontsize=11)
    ax.xaxis.set_major_formatter(mtick.PercentFormatter(decimals=0))
    fig.tight_layout()
    fig.savefig(CHARTS / "04_industry_employment_change_2020.png")
    plt.close(fig)


def chart_yoy(f):
    df = f["a_earnings_yoy"].dropna()
    fig, ax1 = plt.subplots(figsize=(8, 4))
    ax1.bar(df["period"], df["yoy_pct"], color=BLUE, label="Median weekly pay, YoY %")
    ax1.plot(df["period"], df["ft_workers_yoy_pct"], color=RED, lw=2, marker="o", ms=3,
             label="Full-time workers counted, YoY %")
    ax1.axhline(0, color="black", lw=0.8)
    ax1.set_xticks(range(0, len(df), 4), df["period"].iloc[::4], rotation=0)
    ax1.yaxis.set_major_formatter(mtick.PercentFormatter(decimals=0))
    ax1.legend(frameon=False, loc="upper left")
    fig.suptitle("2020 pay 'spike' is a composition effect: low-wage jobs disappeared", x=0.02, ha="left", fontsize=11)
    fig.tight_layout()
    fig.savefig(CHARTS / "05_yoy_pay_vs_headcount.png")
    plt.close(fig)


def export_dashboard_data(f):
    def records(name, cols=None):
        df = f[name] if cols is None else f[name][cols]
        df = df.copy()
        for c in df.columns:
            if str(df[c].dtype).startswith("datetime"):
                df[c] = df[c].dt.strftime("%Y-%m-%d")
        return json.loads(df.to_json(orient="records"))

    payload = {
        "earningsBySex": records("a_earnings_by_sex_quarterly"),
        "earningsYoy": records("a_earnings_yoy"),
        "payRatioByYear": records("a_pay_ratio_by_year"),
        "payRatioByCategory": records("a_pay_ratio_by_category"),
        "occupationRanking": records("a_occupation_gap_ranking"),
        "occupationScatter": records("a_occupation_scatter"),
        "femaleShareBands": records("a_female_share_bands"),
        "industryShock": records("a_industry_shock"),
        "employmentTrend": records("a_employment_trend"),
        "earningsByRace": records("a_earnings_by_race"),
        "genderRatioByAge": records("a_gender_ratio_by_age"),
        "dqReport": records("dq_report"),
    }
    DASH_DATA.write_text("// built by src/run_pipeline.py\n"
                         "window.DASHBOARD_DATA = " + json.dumps(payload) + ";\n")
    print("  wrote dashboard/data.js")


def main():
    print("1/4 Building DuckDB database")
    con = build_database()

    print("2/4 Data quality")
    print(con.execute("SELECT * FROM dq_report").df().to_string(index=False))
    rec = con.execute("SELECT * FROM dq_employment_reconciliation").df()
    print(rec.to_string(index=False))
    assert (rec["sectors"] == 13).all(), "expected 13 sectors per year"
    assert ((rec["total_employed"] - rec["men_plus_women"]).abs() <= 13_000).all(), \
        "men + women should reconcile to total (within rounding of 13 sectors x 1k)"

    print("3/4 Exporting analysis tables")
    frames = export_tables(con)

    print("4/4 Charts + dashboard data")
    CHARTS.mkdir(parents=True, exist_ok=True)
    for fn in (chart_pay_ratio_trend, chart_category_gap, chart_scatter,
               chart_industry_shock, chart_yoy):
        fn(frames)
    export_dashboard_data(frames)
    con.close()
    print("Done.")


if __name__ == "__main__":
    main()
