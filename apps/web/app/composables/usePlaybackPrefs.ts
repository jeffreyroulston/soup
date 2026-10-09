/** Playback defaults set in Settings. Kept per browser, like the player's volume would be. */
export type PlaybackPrefs = {
  /** Count down and start the next episode when credits begin. */
  autoplayNext: boolean
  /** Jump past intros and recaps without waiting for a click. */
  autoSkipIntros: boolean
  /** Quality cap in bits/s for new playback, or null for Auto. */
  maxBitrate: number | null
  /** ISO 639-2 code, or null for the file's default track. */
  audioLanguage: string | null
  /** ISO 639-2 code, or null for subtitles off. */
  subtitleLanguage: string | null
}

const STORAGE_KEY = 'soup.playbackPrefs'

const DEFAULTS: PlaybackPrefs = {
  autoplayNext: true,
  autoSkipIntros: false,
  maxBitrate: null,
  audioLanguage: null,
  subtitleLanguage: null,
}

/** Languages offered in Settings; codes are the forms Jellyfin reports (see `matchesLanguage`). */
export const PREF_LANGUAGES: { code: string, label: string }[] = [
  { code: 'eng', label: 'English' },
  { code: 'ara', label: 'Arabic' },
  { code: 'chi', label: 'Chinese' },
  { code: 'dan', label: 'Danish' },
  { code: 'dut', label: 'Dutch' },
  { code: 'fin', label: 'Finnish' },
  { code: 'fre', label: 'French' },
  { code: 'ger', label: 'German' },
  { code: 'hin', label: 'Hindi' },
  { code: 'ita', label: 'Italian' },
  { code: 'jpn', label: 'Japanese' },
  { code: 'kor', label: 'Korean' },
  { code: 'nor', label: 'Norwegian' },
  { code: 'pol', label: 'Polish' },
  { code: 'por', label: 'Portuguese' },
  { code: 'rus', label: 'Russian' },
  { code: 'spa', label: 'Spanish' },
  { code: 'swe', label: 'Swedish' },
  { code: 'tur', label: 'Turkish' },
]

function load(): PlaybackPrefs {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    const saved = raw ? JSON.parse(raw) as Partial<PlaybackPrefs> : {}
    return { ...DEFAULTS, ...saved }
  }
  catch {
    return { ...DEFAULTS }
  }
}

export function usePlaybackPrefs() {
  const prefs = useState<PlaybackPrefs>('playbackPrefs', load)

  function update(patch: Partial<PlaybackPrefs>) {
    prefs.value = { ...prefs.value, ...patch }
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs.value))
    }
    catch {
      // Private mode or full storage: the change still applies for this visit.
    }
  }

  return { prefs: readonly(prefs), update }
}
