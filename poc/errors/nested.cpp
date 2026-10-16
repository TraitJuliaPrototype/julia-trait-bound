#include <map>
#include <string>
#include <vector>
#include <algorithm>
struct Point { double x, y; };
int main() {
  std::map<std::string, std::vector<std::pair<std::string, Point>>> m;
  auto& v = m["a"];
  std::sort(v.begin(), v.end());   // Point has no operator<
}
