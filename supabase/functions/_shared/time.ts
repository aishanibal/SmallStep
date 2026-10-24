// Clock helpers. Everything is computed in the participant's time zone.

export const mod = (n: number, m: number) => ((n % m) + m) % m;

/** "07:30" or "07:30:00" -> minutes after midnight. */
export function parseClock(t: string): number {
  const m = /^(\d{1,2}):(\d{2})/.exec(t);
  if (!m) throw new Error(`bad clock time: ${t}`);
  return Number(m[1]) * 60 + Number(m[2]);
}

const formatters = new Map<string, Intl.DateTimeFormat>();

/** Minutes after local midnight for `d` in `timeZone`. */
export function localMinuteOfDay(d: Date, timeZone: string): number {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "numeric", hourCycle: "h23" });
    formatters.set(timeZone, f);
  }
  const parts = f.formatToParts(d);
  const get = (type: string) => Number(parts.find((p) => p.type === type)!.value);
  return get("hour") * 60 + get("minute");
}

/** "Tuesday" for `d` in `timeZone`. */
export function localWeekday(d: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone, weekday: "long" }).format(d);
}

export type TimeOfDay = "morning" | "afternoon" | "evening";
export const TIME_OF_DAY_ORDER: TimeOfDay[] = ["morning", "afternoon", "evening"];

export function timeOfDay(minuteOfDay: number): TimeOfDay {
  if (minuteOfDay < 12 * 60) return "morning";
  if (minuteOfDay < 17 * 60) return "afternoon";
  return "evening";
}

export type GapBucket = "short" | "medium" | "long";
export const GAP_BUCKET_ORDER: GapBucket[] = ["short", "medium", "long"];
export const GAP_BUCKET_LABEL: Record<GapBucket, string> = { short: "≤15m", medium: "16-30m", long: ">30m" };

export function gapBucket(minutes: number): GapBucket {
  if (minutes <= 15) return "short";
  if (minutes <= 30) return "medium";
  return "long";
}
