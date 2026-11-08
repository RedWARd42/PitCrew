import { z } from "zod";
export const contactsSchema = z.record(
  z.string(),
  z.string().regex(/^\+[1-9]\d{7,14}$/),
);
export function contacts() {
  return contactsSchema.parse(
    JSON.parse(process.env.PHOTON_PEOPLE_JSON ?? "{}"),
  );
}
export function allowedPhone(personId: string) {
  const phone = contacts()[personId];
  const allowlist = (process.env.PHOTON_RECIPIENT_ALLOWLIST ?? "")
    .split(",")
    .map((s) => s.trim());
  if (!phone || !allowlist.includes(phone))
    throw new Error("Recipient has not been configured and opted in");
  return phone;
}
