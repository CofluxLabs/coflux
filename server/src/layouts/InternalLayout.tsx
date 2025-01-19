import { Outlet } from "react-router-dom";
import { SocketProvider } from "@topical/react";

export default function InternalLayout() {
  return (
    <SocketProvider url={`ws://${window.location.host}/topics`}>
      <div className="flex flex-col min-h-screen max-h-screen overflow-hidden lg:p-2 bg-cyan-600">
        <Outlet />
      </div>
    </SocketProvider>
  );
}
