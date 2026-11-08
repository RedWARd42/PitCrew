import type { FleetState, FleetTicket, SectorId } from "./fleet";

/** A review acknowledges operational facts, not a clock tick or another acknowledgement. */
export function shiftBriefSignature(state: FleetState): string {
  const payload = JSON.stringify({
    tickets: state.tickets.map((t) => [
      t.id,
      t.status,
      t.assigneeId,
      t.priority,
      t.steps.map((s) => [s.id, s.completed, s.note, s.completedBy]),
      t.handoff.summary,
    ]),
    incidents: state.incidents.map((i) => [
      i.id,
      i.status,
      i.severity,
      i.summary,
    ]),
    plans: state.maintenancePlans.map((p) => [
      p.id,
      p.status,
      p.ticketId,
      p.blockers.map((b) => [b.id, b.clearedAt, b.clearedBy, b.note]),
    ]),
    coverage: state.technicians.map((t) => [
      t.id,
      t.available,
      t.onCall,
      t.checkedInSector,
      t.subscriptions,
    ]),
  });
  let hash = 2166136261;
  for (let i = 0; i < payload.length; i++)
    hash = Math.imul(hash ^ payload.charCodeAt(i), 16777619);
  return (hash >>> 0).toString(16);
}
/** Client-safe work ordering. Distance is seeded indoor adjacency, never travel time. */
export function rankTechnicianQueue(
  state: FleetState,
  technicianId: string,
): FleetTicket[] {
  const technician = state.technicians.find((t) => t.id === technicianId);
  const positions: Record<SectorId, number> = { A: 0, B: 3, C: 5 };
  const continuation = (ticket: FleetTicket) =>
    Number(["accepted", "in_progress"].includes(ticket.status));
  const due = (ticket: FleetTicket) =>
    ticket.dueAt ? Date.parse(ticket.dueAt) : Number.MAX_SAFE_INTEGER;
  const distance = (ticket: FleetTicket) =>
    technician
      ? Math.abs(
          positions[ticket.sectorId] - positions[technician.checkedInSector],
        )
      : 0;
  return state.tickets
    .filter((t) => t.assigneeId === technicianId && t.status !== "resolved")
    .sort(
      (a, b) =>
        Number(b.priority === "critical") - Number(a.priority === "critical") ||
        continuation(b) - continuation(a) ||
        due(a) - due(b) ||
        distance(a) - distance(b) ||
        a.createdAt.localeCompare(b.createdAt),
    );
}
