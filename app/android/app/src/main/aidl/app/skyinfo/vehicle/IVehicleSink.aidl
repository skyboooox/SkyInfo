package app.skyinfo.vehicle;
oneway interface IVehicleSink {
    void onSample(String id, String sample);
    void onStatus(String state);
}
