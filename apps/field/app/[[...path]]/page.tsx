import FieldApp from "../../components/field-app";
import FleetApp from "../../components/fleet-app";

export default async function Page({
  params,
}: {
  params: Promise<{ path?: string[] }>;
}) {
  const { path = [] } = await params;
  const fleetPage =
    path.length === 0 ||
    [
      "sectors",
      "tickets",
      "team",
      "activity",
      "fleet",
      "brief",
      "upkeep",
    ].includes(path[0]);
  return fleetPage ? <FleetApp /> : <FieldApp />;
}
