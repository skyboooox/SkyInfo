package app.skyinfo.vehicle;
import app.skyinfo.vehicle.IVehicleSink;
interface IVehicleSource {
    void destroy() = 16777114;
    String identity() = 0;
    String read(String id) = 1;
    String subscribe(in String[] ids, IVehicleSink sink) = 2;
    void cancel() = 3;
    String control(String action, int value) = 4;
    String controls() = 5;
}
