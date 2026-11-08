/** PitCrew: two interlocking survey planes around a fixed reference point. */
export default function BrandMark({ className = "" }: { className?: string }) {
  return (
    <svg
      className={`brand-symbol ${className}`}
      viewBox="0 0 48 48"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M24 4 44 15.5 24 27 4 15.5 24 4Z"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinejoin="round"
      />
      <path
        d="m4 24 20 11.5L44 24M4 32.5 24 44l20-11.5"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M24 27v17M24 4v8" stroke="currentColor" strokeWidth="2.4" />
      <path d="m24 12 6 3.5-6 3.5-6-3.5 6-3.5Z" fill="currentColor" />
    </svg>
  );
}
