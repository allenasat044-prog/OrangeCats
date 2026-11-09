import { faqs } from "../data";

export default function FAQ() {
  return (
    <>
      <h1>Frequently asked questions</h1>
      {faqs.map((f) => (
        <details key={f.q}>
          <summary>{f.q}</summary>
          <p>{f.a}</p>
        </details>
      ))}
    </>
  );
}
