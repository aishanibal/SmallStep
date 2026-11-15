// The one place that decides which activities are too intense right after a meal.
// Applies to every source (A, B, C). Change the numbers or lists here; nothing else needs touching.

/** Minutes left free between an activity and whatever comes next, when the participant has not chosen. */
export const DEFAULT_TRANSITION_MIN = 5;

export interface MealRules {
  /** No high-intensity activity may overlap the window from a meal time to this many minutes after. */
  minutesAfterMeal: number;
  /** Activity categories (lowercase) treated as high intensity. */
  highIntensityCategories: string[];
  /** For Source B, which has no category: words in its title/description that mark high intensity. */
  highIntensityKeywords: string[];
}

export const MEAL_RULES: MealRules = {
  minutesAfterMeal: 60,
  highIntensityCategories: ["strength", "running", "cardio", "hiit"],
  highIntensityKeywords: ["run", "jog", "sprint", "hiit", "cardio", "lift", "strength", "workout", "burpee", "intense"],
};
