use std::{
    io::prelude::*,
    net::{TcpListener, TcpStream},
};
use std::process::{Command, Stdio};


fn handle_client(mut stream: TcpStream) {

    //Get raw tcp data
    let mut tcp_raw: [u8 ; 512] = [0; 512];
    stream.read(&mut tcp_raw).unwrap();

    interpret_packet(&mut tcp_raw, &mut stream);

}

fn interpret_packet(packet_raw : &mut [u8 ; 512], stream: &mut TcpStream) {

    const F_POST_ADD    : &str = "POST /add HTTP/1.1";
    const F_POST_DEL    : &str = "POST /delete HTTP/1.1";
    const F_POST_FETCH  : &str = "POST /fetch HTTP/1.1";
    const RSP_200  : &str = "HTTP/1.1 200 OK\r\n\r\n";
    const RSP_404  : &str = "HTTP/1.1 404 Not Found\r\n\r\n";


    let v_str_packet_lines: Vec<_> = packet_raw
        .lines()
        .map(|result| result)
        .take(200)
        .collect();

    match &v_str_packet_lines[0].as_ref().unwrap().as_str() {
        &F_POST_ADD | &F_POST_DEL => {
            if trigger_script(&extract_yt_id(&v_str_packet_lines),"add") {
                stream.write_all(&RSP_200.as_bytes()).unwrap();
            } else {
                stream.write_all(RSP_404.as_bytes()).unwrap();
            }
        },
        &F_POST_FETCH => {
            if trigger_script(&extract_yt_id(&v_str_packet_lines),"fetch") {
                stream.write_all(&RSP_200.as_bytes()).unwrap();
            } else {
                stream.write_all(RSP_404.as_bytes()).unwrap();
            }
        },
        _ => {
            stream.write_all(RSP_404.as_bytes()).unwrap();
        },
    }

}

fn extract_yt_id(v_str_packet_lines : &Vec<Result<String, std::io::Error>> ) -> String {
    let mut output = String::new();
    for i in v_str_packet_lines.iter() {
        match i.as_ref().unwrap().find("yt_id")
        {
            Some(_x) => {
                output=i.as_ref()
                        .unwrap()
                        .replace("yt_id","")
                        .chars()
                        .filter(|x| (
                            (*x>='a' && *x<='z') ||
                            (*x>='A' && *x<='Z') ||
                            (*x>='0' && *x<='9') ||
                            (*x=='-')            ||
                            (*x=='_')
                        ))
                        .collect::<String>();
                break
            },
            _ => (),
        }
    }
    output
}


fn trigger_script(yt_id: &String, action: &str) -> bool{
    if !yt_id.is_empty() {
        let cmd = Command::new("./media_controller.sh")
            .args([
                action,
                yt_id,
            ])
            //.stdout(Stdio::piped())
            .status()
            .expect("failed to execute command");

        if cmd.success() {
            println!("Action {} for {} -> successful", action, yt_id);
            return true;
        } else {
            println!("Action {} for {} -> failed", action, yt_id);
            return false;
        }
    } else {
        return false;
    }
}
fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("0.0.0.0:8123")?;

    // accept connections and process them serially
    for stream in listener.incoming() {
        handle_client(stream?);
    }
    Ok(())
}