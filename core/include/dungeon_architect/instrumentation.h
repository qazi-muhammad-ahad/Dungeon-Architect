#pragma once
#include <chrono>
#include <map>
#include <string>
namespace dungeon_architect {
using TimingMap = std::map<std::string, double>;
class PhaseClock {
    using Clock = std::chrono::steady_clock;
    Clock::time_point last = Clock::now();
    std::string phase;
public:
    TimingMap values;
    explicit PhaseClock(std::string first) : phase(std::move(first)) {}
    void next(std::string name) {
        const auto now = Clock::now();
        values[phase] += std::chrono::duration<double,std::micro>(now-last).count();
        last = now; phase = std::move(name);
    }
};
class TraceClock {
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    double& value;
public:
    explicit TraceClock(double& out) : value(out) {}
    ~TraceClock() { value += std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-start).count(); }
};
}
